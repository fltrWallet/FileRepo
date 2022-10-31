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
#if canImport(Foundation)
import Foundation
import NIOCore
import NIOPosix

public extension File {
    static func rename(file: String,
                       to: String,
                       eventLoop: EventLoop,
                       threadPool: NIOThreadPool) -> EventLoopFuture<Void> {
        threadPool.runIfActive(eventLoop: eventLoop) {
            try? FileManager.default.removeItem(atPath: to)
            return try FileManager.default.moveItem(atPath: file, toPath: to)
        }
    }
    
    static func delete(file: String,
                       eventLoop: EventLoop,
                       threadPool: NIOThreadPool) -> EventLoopFuture<Void> {
        threadPool.runIfActive(eventLoop: eventLoop) {
            try FileManager.default.removeItem(atPath: file)
        }
    }

}
#endif
