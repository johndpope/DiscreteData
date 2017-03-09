
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

import CKit
import func Foundation.memcpy

extension DiscreteData {
    class _FragmentContainer {

        var fragments = [DataFragment]()
        var length: Int

        init (fragments: [DataFragment]) {
            self.fragments = fragments
            self.length = fragments.reduce(0) {
                $0 + $1.o_len
            }
        }

        /// Fragment of data
        init(capacity: Int) {
            self.fragments.append(DataFragment(bytes: capacity))
            self.length = capacity
        }

        init(bytes: PointerType, length: Int, free: @escaping (UnsafeMutableRawPointer, Int) -> ()) {
            self.fragments.append(DataFragment(base: bytes, length: length, free: free))
            self.length = length
        }

        init(buffer: PointerType, length: Int) {
            self.fragments.append(DataFragment(buffer: buffer, length: length))
            self.length = length
        }

        convenience init<T>(bytes: UnsafePointer<T>, length: Int, free: @escaping (UnsafeMutableRawPointer, Int) -> ()) {
            self.init(bytes: bytes, length: length, free: free)
        }

        convenience init<T>(buffer: UnsafePointer<T>, length: Int) {
            self.init(buffer: buffer, length: length)
        }

        init(copy: _FragmentContainer, offset: Int, length: Int) {

            self.length = length
            if length == 0 {
                return
            }

            var (fragments, front, back) = copy.affectingFragments(offset: offset, count: length)

            var frontFragment: DataFragment?
            var backFragment: DataFragment?

            if fragments.count == 0 {
                fatalError("No segments found ")
            }

            if front != 0 {
                frontFragment = fragments.removeFirst().copy()
                frontFragment = frontFragment!.split(at: front)
            }

            if fragments.count > 1 && back != 0  {
                backFragment = fragments.removeLast().copy()
                _ = backFragment!.split(at: backFragment!.iovec.iov_len - back)
            }

            for fragment in fragments {
                self.fragments.append(fragment)
            }

            if let f = frontFragment {
                self.fragments.insert(f, at: 0)
            }

            if let b = backFragment {
                self.fragments.append(b)
            }
        }

    }
}

// MARK: FragmentContainer Implementation
extension DiscreteData._FragmentContainer {
    func subdata(from offset: Int, to end: Int) -> DiscreteData._FragmentContainer {
        return subdata(from: offset, len: end - offset + 1)
    }

    func subdata(from offset: Int, len: Int) -> DiscreteData._FragmentContainer {
        return DiscreteData._FragmentContainer(copy: self, offset: offset, length: len)
    }

    func modify(from offset: Int, with buffer: UnsafeMutableRawPointer, len: Int) {

    }

    func replace(offset: Int, len: Int, with other: DiscreteData._FragmentContainer) {
        
    }

    func getBytes(from offset: Int, length: Int, to dest: UnsafeMutableRawPointer) {
        var _fragments = [DataFragment]()
        var front = 0
        (_fragments, front, _) = affectingFragments(offset: offset, count: length)

        var off = 0 - front

        for fragment in _fragments {

            let llen = off + fragment.iovec.iov_len > length
                ? length
                : fragment.iovec.iov_len

            memcpy(dest + off, fragment.iovec.iov_base, llen)
            off += fragment.iovec.iov_len
        }
    }

    func append(data: DiscreteData._FragmentContainer) {
        self.fragments.append(contentsOf: data.fragments)
    }

    func insert(data: DiscreteData._FragmentContainer, at _offset_: Int) {
        if _offset_ > self.length {
            self.append(data: data)
            return
        }

        let (index, offset) = fragment(at: _offset_)
        self.length += data.length

        if (offset == 0) {
            self.fragments.insert(contentsOf: data.fragments, at: index)
            return
        }

        let segment = self.fragments[index]

        let (newBlock, check) = segment.partition(offset: offset, len: segment.o_len - offset)!

        if check != nil {
            fatalError("Cannot insert: partition checksum failed")
        }

        self.fragments.insert(contentsOf: data.fragments, at: index + 1)
        self.fragments.insert(newBlock, at: index + data.fragments.count + 1)
    }

    /// Finding fragments in the range from `offset` with length `count`
    ///
    /// - Parameters:
    ///   - offset: starting location respect to the beginning
    ///   - count: length of the fragment
    /// - Returns: return a tuple of (segments, off_front, off_back), segments returns affected segments, off_front is the offset of the frist segment and off_back is the offset of the last segment
    func affectingFragments(offset: Int, count: Int) -> (segments: [DataFragment], off_front: Int, off_back: Int) {

        var partialSum = 0
        var _fragments_ = [DataFragment]()

        var off_back = 0
        var off_front = 0

        for fragment in fragments {

            if partialSum < offset {
                partialSum += fragment.o_len

                if !(partialSum <= offset) {
                    off_front = partialSum - fragment.o_len + offset
                } else {
                    continue
                }
            } else {
                partialSum += fragment.o_len
            }
            _fragments_.append(fragment)

            if partialSum > count + off_front  {
                off_back = partialSum - offset - count
                break
            }
        }

        return (_fragments_, off_front, off_back)
    }

    /// The fragment of the byte at `offset` located at
    ///
    /// - Parameter offset: the offset
    /// - Returns: a duple of (index, offset) where index is the index of the fragment in the fragments array, offset is the offset from the begining of the fragment
    func fragment(at offset: Int) -> (index: Int, offset: Int) {
        if offset > self.length {
            fatalError("segment not exist")
        }

        var total = offset

        for (index, fragment) in fragments.enumerated() {
            if total - fragment.o_len <= 0 {
                return (index, total)
            }
            total -= fragment.o_len
        }

        return (0, 0)
    }
}
