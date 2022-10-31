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
import NIOCore

public protocol HeaderRepoProtocol: FileRepo where Model.ID == Int {
    func heights() -> EventLoopFuture<(lowerHeight: Int, upperHeight: Int)>
}

public extension HeaderRepoProtocol {
    @inlinable func heights() -> EventLoopFuture<(lowerHeight: Int, upperHeight: Int)> {
        self.range().map {
            (lowerHeight: $0.lowerBound, upperHeight: max($0.upperBound - 1, 0))
        }
    }
}
