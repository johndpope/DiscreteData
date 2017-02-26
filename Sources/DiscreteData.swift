import Foundation
import CKit

func sizeof<T>(_ type: T.Type) -> Int {
    return MemoryLayout<T>.size
}

fileprivate typealias iovec_ = Foundation.iovec


/// Descrete Data
struct DiscreteData {
    
    class _FragmentContainer {
        
        var fragments = [DataFragment]() // should use ordered set
        
        /// Fragment of data
        class DataFragment {
            
            // base pointer and length
            fileprivate var iovec: iovec {
                return iovec_(iov_base: v_base.advanced(by: o_off), iov_len: o_len)
            }
            
            // the "root" location of this memory segment (where the real malloc/mmap/etc returns)
            // since a segment can be child of other segments, comparing the base pointer can
            // determine if they're coming from the same root
            var base: UnsafeMutableRawPointer!
            
            fileprivate var v_base: UnsafeMutableRawPointer {
                if let parent = self.parent {
                    return parent.v_base
                }
                return base
            }
            
            // the address of this segment offset to root location,
            // so the actual pointer this segment stores will be base + o_off
            fileprivate var o_off: Int
            
            // how big is this buffert
            fileprivate var o_len: Int
            
            // the free function (if the segment is allocated)
            private var free_: (UnsafeMutableRawPointer, Int) -> ()
            
            // point to the segment that's created by malloc
            private var parent: DataFragment?
            
            
            /// Init empty buffer with capacity
            ///
            /// - Parameter bytes: the size of buffer
            fileprivate init(bytes: Int) {
                
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
            
            
            /// Init with preallocated buffer
            ///
            /// - Parameters:
            ///   - base: the location of the buffer
            ///   - length: the size of the buffer
            ///   - free: the function to deallocate
            fileprivate init(base: UnsafeMutableRawPointer, length: Int, free:  @escaping (UnsafeMutableRawPointer, Int) -> ()) {
                self.base = base
                self.o_len = length
                self.o_off = 0
                self.free_ = free
            }
            
            /// Init and copy from payload in another buffer
            ///
            /// - Parameters:
            ///   - buffer: The buffer copy from
            ///   - length: how many bytes to copy
            fileprivate convenience init(buffer: UnsafeRawPointer, length: Int) {
                // allcoate internal buffer
                let buf = malloc(length)
                // copy bytes
                memcpy(buf, buffer, length)
                // and initialize with free (since allocate with malloc)
                self.init(base: buf!, length: length, free: {free($0.0)})
            }
            
            /// Init and copy from payload in another buffer
            ///
            /// - Parameters:
            ///   - buffer: The buffer copy from
            ///   - length: how many bytes to copy
            fileprivate convenience init<T>(buffer: UnsafePointer<T>, length: Int) {
                let buf = malloc(length)
                memcpy(buf, buffer, length)
                self.init(base: buf!, length: length, free: {free($0.0)})
            }
            
            /// Init as a reference to another fragment
            ///
            /// - Parameters:
            ///   - parent: The fregment referencing to
            ///   - off: offset to the parent buffer
            ///   - len: length of this new buffer
            fileprivate init(parent: DataFragment, off: Int, len: Int) {
                
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
            
            private func overlapped(with other: DataFragment) -> Bool {
                return
                    min(self.iovec.iov_base, other.iovec.iov_base) == self.iovec.iov_base ?
                        (self.iovec.iov_base + self.iovec.iov_len) > other.iovec.iov_base :
                        (self.iovec.iov_base + self.iovec.iov_len) < other.iovec.iov_base
            }
            
            
            /// Split this fragment into 2
            ///
            /// - Parameter offset: the split position
            /// - Returns: nil if cannot split, otherwise the new fragment sperate from `self`
            fileprivate func split(at offset: Int) -> DataFragment? {
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
            fileprivate func partition(offset: Int, len: Int) -> (front: DataFragment, back: DataFragment?)? {
                guard let front = self.split(at: offset) else {
                    return nil
                }
                return (front, front.split(at: front.o_len - len))
            }
            
            private func isLower(than other: DataFragment) -> Bool {
                return self.v_base < other.v_base
            }
            
            /// If the other fragment has the same parent (means the memory segment these fragment are allocated from the same malloc()/mmap() call
            private func isRelative(with other: DataFragment) -> Bool {
                return self.v_base == other.v_base
            }
            
            /// dereference self.parent
            private func release() {
                self.parent = nil
            }
            
            
            /// Combine with the other fragment into a single, contingous fragment
            private func merge(with b: DataFragment) -> DataFragment? {
                
                //==============================================================//
                //                                                              //
                // WARNING: ASSUMING self IS ALWAYS IN LOWER ADDRESS THAN b     //
                //                                                              //
                //==============================================================//
                
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
                
                memcpy(newBuf.base, lowerBase, lowerLen)
                memcpy(newBuf.base + lowerLen, higherBase, higherLen)
                
                self.release()
                b.release()
                
                return newBuf
            }
            
            /// Combines an array of fragments into a single contingous fragment
            fileprivate static func merge(fragments: [DataFragment]) -> DataFragment {
                
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
            
            /// this fragment is not an reference to another fragment
            private func isIndependent() -> Bool {
                return self.parent == nil
            }
            
            private func contiguous(with other: DataFragment) -> Bool {
                if overlapped(with: other) {
                    return false
                }
                
                if min(self.iovec.iov_base, other.iovec.iov_base) == self.iovec.iov_base {
                    return (self.iovec.iov_base + self.iovec.iov_len) == other.iovec.iov_base
                } else {
                    return self.iovec.iov_base == (other.iovec.iov_base + other.iovec.iov_len)
                }
            }
            
            private func concretize() {
                guard let _ = parent else {
                    return
                }
                
                let obase = self.v_base
                self.base = malloc(o_len)
                memcpy(self.v_base, obase.advanced(by: self.o_off), o_len)
                
                self.o_off = 0
                self.parent = nil // dereference
            }
            
            deinit {
                free_(iovec.iov_base, iovec.iov_len)
            }
        }
        
        init(capacity: Int) {
            self.fragments.append(DataFragment(bytes: capacity))
            self.length = capacity
        }
        
        init(bytes: UnsafeMutableRawPointer, length: Int, free: @escaping (UnsafeMutableRawPointer, Int) -> ()) {
            self.fragments.append(DataFragment(base: bytes, length: length, free: free))
            self.length = length
        }
        
        init(buffer: UnsafeRawBufferPointer, length: Int) {
            self.fragments.append(DataFragment(buffer: buffer.baseAddress!, length: length))
            self.length = length
        }
        
        init<T>(buffer: UnsafePointer<T>, length: Int) {
            self.fragments.append(DataFragment(buffer: buffer, length: length))
            self.length = length
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
                frontFragment = fragments.removeFirst()
                frontFragment = frontFragment!.split(at: front)
            }
            
            if fragments.count > 1 && back != 0  {
                backFragment = fragments.removeLast()
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
        
        func subdata(from offset: Int, to end: Int) -> _FragmentContainer {
            
            return subdata(from: offset, len: end - offset + 1)
        }
        
        func subdata(from offset: Int, len: Int) -> _FragmentContainer {
            return _FragmentContainer(copy: self, offset: offset, length: len)
        }
        
        func modify(from offset: Int, with buffer: UnsafeMutableRawPointer, len: Int) {
            
        }
        
        func replace(offset: Int, len: Int, with other: _FragmentContainer) {
            
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
        
        func append(data: _FragmentContainer) {
            self.fragments.append(contentsOf: data.fragments)
        }
        
        var length: Int
        
        func insert(data: _FragmentContainer, at _offset_: Int) {
            
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
        
        private func affectingFragments(offset: Int, count: Int) -> (segments: [DataFragment], off_front: Int, off_back: Int) {
            
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
                
                if partialSum > count {
                    off_back = partialSum - offset - count
                    break
                }
            }
            
            return (_fragments_, off_front, off_back)
        }
        
        private func fragment(at offset: Int) -> (index: Int, offset: Int) {
            
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
}









