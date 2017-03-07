

//  Copyright (c) 2016, Yuji
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those
//  of the authors and should not be interpreted as representing official policies,
//  either expressed or implied, of the FreeBSD Project.
//
//  Created by Yuji on 2/26/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import protocol CKit.PointerType
import xlibc

typealias ciovec = xlibc.iovec

class DataFragment {

    // base pointer and length
    var iovec: iovec {
        return ciovec(iov_base: v_base.advanced(by: o_off), iov_len: o_len)
    }

    // the "root" location of this memory segment (where the real malloc/mmap/etc returns)
    // since a segment can be child of other segments, comparing the base pointer can
    // determine if they're coming from the same root
    var base: UnsafeMutableRawPointer!

    // the free function (if the segment is allocated)
    fileprivate var free_: (UnsafeMutableRawPointer, Int) -> ()

    // point to the segment that's created by malloc
    var parent: DataFragment?

    var v_base: UnsafeMutableRawPointer {
        if let parent = self.parent {
            return parent.v_base
        }
        return base
    }

    // the address of this segment offset to root location,
    // so the actual pointer this segment stores will be base + o_off
    var o_off: Int

    // how big is this buffert
    var o_len: Int

    /// Init empty buffer with capacity
    ///
    /// - Parameter bytes: the size of buffer
    init(bytes: Int) {

        // allocate memory
        base = malloc(bytes)

        // since we're fresh, our offset is 0
        self.o_off = 0

        // the length we're storing is same as the bytes we allocated
        o_len = bytes

        // since we use malloc, we use free here
        free_ = { (ptr: UnsafeMutableRawPointer, len: Int) in
            free(ptr)
        }
    }

    /// Init as a reference to another fragment
    ///
    /// - Parameters:
    ///   - parent: The fregment referencing to
    ///   - off: offset to the parent buffer
    ///   - len: length of this new buffer
    init(parent: DataFragment, off: Int, len: Int) {

        // get the parent
        var p: DataFragment? = parent

        // since our parent at this point can be either a prime segment or not.
        // so we need to calculate the offset to base pointer of the parent
        // and the offset we required
        o_off = parent.o_off + off
        o_len = len

        // loop until we find the real parent (prime segment)
        while p?.parent != nil {
            p = p?.parent
        }

        self.parent = p

        // we dont need to free anything
        free_ = {_,_ in }
    }

    /// Init with preallocated buffer
    ///
    /// - Parameters:
    ///   - base: the location of the buffer
    ///   - length: the size of the buffer
    ///   - free: the function to deallocate
    init(base: PointerType, length: Int, free:  @escaping (UnsafeMutableRawPointer, Int) -> ()) {
        self.base = UnsafeMutableRawPointer(mutating: base.rawPointer)
        self.o_len = length
        self.o_off = 0
        self.free_ = free
    }
    deinit {
        free_(iovec.iov_base, iovec.iov_len)
    }
}


// MARK: initializations
extension DataFragment {

    /// Init and copy from payload in another buffer
    ///
    /// - Parameters:
    ///   - buffer: The buffer copy from
    ///   - length: how many bytes to copy
    convenience init(buffer: PointerType, length: Int) {
        // allcoate internal buffer
        let buf = malloc(length)

        guard let _buf = buf else {
            fatalError("malloc: cannot allocate")
        }
        // copy bytes
        memcpy(_buf, buffer.rawPointer, length)
        // and initialize with free (since allocate with malloc)
        self.init(base: buf!, length: length, free: {free($0.0)})
    }

    convenience init<T>(buffer: UnsafePointer<T>, length: Int) {
        self.init(buffer: buffer, length: length)
    }
}

extension DataFragment {

    /// Split this fragment into 2
    ///
    /// - Parameter offset: the split position
    /// - Returns: nil if cannot split, otherwise the new fragment sperate from `self`
    func split(at offset: Int) -> DataFragment? {
        if offset > self.o_len || offset == 0 {
            return nil
        }

        let ret = DataFragment(parent: self, off: offset, len: self.o_len - offset)
        self.o_len = offset
        return ret
    }

    /// split this fragment into 2 or 3 parts that it can fit a fragment from `offset` with length `len`
    ///
    /// - Parameters:
    ///   - offset: the position of the fragment
    ///   - len: the length of the fragment
    /// - Returns: nil if fragment cannot partition, otherwise return a duple of (front, back?) which represent the first and second fragment
    func partition(offset: Int, len: Int) -> (front: DataFragment, back: DataFragment?)? {
        guard let front = self.split(at: offset) else {
            return nil
        }
        return (front, front.split(at: front.o_len - len))
    }

    /// dereference self.parent
    func release() {
        self.parent = nil
    }

    /// Combine with the other fragment into a single, contingous fragment
    func merge(with b: DataFragment) -> DataFragment? {

        //==================================================//
        //                                                  //
        // ASSUMING self IS ALWAYS IN LOWER ADDRESS THAN b  //
        //                                                  //
        //==================================================//

        if self.contiguous(with: b) {
            if self.isRelative(with: b) {
                self.o_len += b.o_len
                b.release()
                return nil
            }
            // if no new block required, return nothing
        }

        let newBuf = DataFragment(bytes: self.o_len + b.o_len)

        let selfIsLower = self.iovec.iov_base < b.iovec.iov_base
        let lowerBase   = selfIsLower ? self.iovec.iov_base : b.iovec.iov_base
        let lowerLen    = selfIsLower ? self.iovec.iov_len  : b.iovec.iov_len
        let higherBase  = selfIsLower ?    b.iovec.iov_base : self.iovec.iov_base
        let higherLen   = selfIsLower ?    b.iovec.iov_len  : self.iovec.iov_len

        memcpy(newBuf.base, lowerBase!, lowerLen)
        memcpy(newBuf.base + lowerLen, higherBase!, higherLen)

        self.release()
        b.release()

        return newBuf
    }

    /// Combines an array of fragments into a single contingous fragment
    static func merge(fragments: [DataFragment]) -> DataFragment {

        if fragments.count == 0 {
            fatalError("segments passed to \(#function) cannot be empty")
        }

        var seg = fragments.first!
        for (index, segment) in fragments.enumerated() {
            if index == 0 {
                continue
            }

            if let m = seg.isLower(than: segment)
                ? seg.merge(with: segment)
                : segment.merge(with: seg) {
                seg = m
            }
        }
        return seg
    }

    func concretize() {
        guard let _ = parent else {
            return
        }

        let obase = self.v_base
        self.base = malloc(o_len)
        memcpy(self.v_base, obase.advanced(by: self.o_off), o_len)

        self.o_off = 0
        self.parent = nil // dereference
    }
}

// MARK: Fragment Relations
extension DataFragment {
    func overlapped(with other: DataFragment) -> Bool {
        return
            min(self.iovec.iov_base, other.iovec.iov_base) == self.iovec.iov_base ?
                (self.iovec.iov_base + self.iovec.iov_len) > other.iovec.iov_base :
                (self.iovec.iov_base + self.iovec.iov_len) < other.iovec.iov_base
    }

    func isLower(than other: DataFragment) -> Bool {
        return self.v_base < other.v_base
    }

    /// If the other fragment has the same parent (means the memory segment these fragment are allocated from the same malloc()/mmap() call
    func isRelative(with other: DataFragment) -> Bool {
        return self.v_base == other.v_base
    }

    /// this fragment is not an reference to another fragment
    func isIndependent() -> Bool {
        return self.parent == nil
    }

    func contiguous(with other: DataFragment) -> Bool {
        if overlapped(with: other) {
            return false
        }

        if min(self.iovec.iov_base, other.iovec.iov_base) == self.iovec.iov_base {
            return (self.iovec.iov_base + self.iovec.iov_len) == other.iovec.iov_base
        } else {
            return self.iovec.iov_base == (other.iovec.iov_base + other.iovec.iov_len)
        }
    }
}
