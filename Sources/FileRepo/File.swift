//===----------------------------------------------------------------------===//
//
// This source file is part of the FileRepo open source project
//
// Copyright (c) 2022 fltrWallet AG and the FileRepo project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import HaByLo
import NIOCore

public enum File {}

public extension File {
    @inlinable
    static func openFile(path: String,
                         nonBlockingFileIO: NonBlockingFileIOClient,
                         eventLoop: EventLoop) -> EventLoopFuture<NIOFileHandle> {
        nonBlockingFileIO.openFile(path: path,
                                   mode: [.read, .write],
                                   flags: .allowFileCreation(posixMode: 0o600),
                                   eventLoop: eventLoop)
    }
    
    @inlinable
    static func closeRecover(on eventLoop: EventLoop,
                             _ futures: (() -> EventLoopFuture<Void>)...) -> EventLoopFuture<Void> {
        self.close(on: eventLoop, futures)
        .recover {
            logger.error("\($0)")
        }
    }
    
    @inlinable
    static func closeFail(on eventLoop: EventLoop,
                          _ futures: (() -> EventLoopFuture<Void>)...) -> EventLoopFuture<Void> {
        self.close(on: eventLoop, futures)
        .recover {
            preconditionFailure("\($0)")
        }
    }
    
    @inlinable
    static func close(on eventLoop: EventLoop,
                      _ futures: (() -> EventLoopFuture<Void>)...) -> EventLoopFuture<Void> {
        self.close(on: eventLoop, futures)
    }
    
    @inlinable
    static func close(on eventLoop: EventLoop,
                      _ futures: [() -> EventLoopFuture<Void>]) -> EventLoopFuture<Void> {
        
        let promise = eventLoop.makePromise(of: Void.self)

        EventLoopFuture.whenAllComplete(futures.map({$0()}), on: eventLoop)
        .whenSuccess {
            let failures: [Swift.Error] = $0.compactMap {
                switch $0 {
                case .failure(let error):
                    return error
                case .success:
                    return nil
                }
            }
            
            if failures.isEmpty {
                promise.succeed(())
            } else {
                promise.fail(CompoundError(failures))
            }
        }
        
        return promise.futureResult
    }
}

internal extension File {
    @usableFromInline
    struct CompoundError: Swift.Error, CustomStringConvertible {
        @usableFromInline
        let value: [Swift.Error]
        
        @usableFromInline
        init(_ value: [Swift.Error]) {
            precondition(!value.isEmpty)
            self.value = value
        }
        
        @usableFromInline
        var description: String {
            var str: [String] = [ "File.close(...) finished with errors:" ]
            for (i, e) in value.enumerated() {
                str.append("\n\t\(i):\t")
                str.append("\(e)")
            }
            
            return str.joined()
        }
    }
}
