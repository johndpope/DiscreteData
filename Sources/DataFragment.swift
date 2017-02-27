
import protocol CKit.PointerType

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
typealias iovec_ = Darwin.iovec
#else
import Glibc
typealias iovec_ = Glibc.iovec
#endif

class DataFragment {
    
    // base pointer and length
    var iovec: iovec {
        return iovec_(iov_base: v_base.advanced(by: o_off), iov_len: o_len)
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
}
        
