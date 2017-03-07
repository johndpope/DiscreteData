
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
    
    public var iovecs: [iovec] {
        return self.container.fragments.map({$0.iovec})
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
