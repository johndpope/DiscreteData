import Foundation
import CKit

/// Descrete Data
public struct DiscreteData {
    fileprivate var container: _FragmentContainer
    fileprivate init(container: _FragmentContainer) {
        self.container = container
    }
}

// MARK: DiscreteData Initialization
extension DiscreteData {

    public init(capacity: Int) {
        container = _FragmentContainer(capacity: capacity)
    }

    public init(buffer: PointerType, length: Int) {
        container = _FragmentContainer(buffer: buffer, length: length)
    }

    public init(bytes: PointerType, length: Int, free: @escaping (UnsafeMutableRawPointer, Int) -> ()) {
        container = _FragmentContainer(bytes: bytes, length: length, free: free)
    }

    public init(copy: DiscreteData, offset: Int, length: Int) {
        container = _FragmentContainer(copy: copy.container, offset: offset, length: length)
    }
}

// MARK: DiscreteData Implementation
extension DiscreteData {

    private enum CError: Error {
        case str(String)
        init(_ str: String) {
            self = .str(str)
        }
    }
    
    public func vwrite(to fd: Int32) throws {
        let iovecs = self.container.fragments.map({$0.iovec})
        if writev(fd, iovecs, Int32(iovecs.count)) == -1 {
            throw(CError(String.lastErrnoString))
        }
    }
    
    public func write(to url: URL, options: Data.WritingOptions = []) throws {
        
        if !url.isFileURL {
            // throw error
        }
        
        if options.contains(.atomic) {
            if options.contains(.withoutOverwriting) {
                // thrownerror
            }
            
            // should change pid to something different, for security reasons
            let tempPath = "/tmp/\(getpid())-\(UUID())"
            
            do {
                try write(to: URL(fileURLWithPath: tempPath))
                rename(tempPath, url.path)
            } catch {
                print(error)
            }
        }
        
        let fd = open(url.path, O_CREAT | O_WRONLY, S_IRUSR | S_IWUSR)
        if fd == -1 {
            throw CError(String.lastErrnoString)
        }
        try vwrite(to: fd)
    }


    public func subdata(from offset: Int, to end: Int) -> DiscreteData {
        return self.subdata(from: offset, len: end - offset + 1)
    }

    public func subdata(from offset: Int, len: Int) -> DiscreteData {
        return DiscreteData(container: self.container.subdata(from: offset, len: len))
    }

    //    func modify(from offset: Int, with buffer: UnsafeMutableRawPointer, len: Int) {
    //
    //    }
    //
    //    func replace(offset: Int, len: Int, with other: _FragmentContainer) {
    //
    //    }
    //

    public func getBytes(from offset: Int, length: Int, to dest: UnsafeMutableRawPointer) {
        self.container.getBytes(from: offset, length: length, to: dest)
    }

    public func append(data: DiscreteData) {
        self.container.append(data: data.container)
    }
}
