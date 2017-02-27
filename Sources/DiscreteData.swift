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

    public func vwrite(to fd: Int32, flags: Int32 = 0) {
        let iovecs = self.container.fragments.map({$0.iovec})
        writev(fd, iovecs, flags)
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
