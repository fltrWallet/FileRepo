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
import FileRepo
#if canImport(Foundation)
import Foundation
#endif
import NIOCore
import NIOPosix
import XCTest

final class FileRepoTests: XCTestCase {
    static let RecordSize = 100
    static let Capacity = 1000
    var threadPool: NIOThreadPool!
    var eventLoopGroup: MultiThreadedEventLoopGroup!
    var eventLoop: EventLoop!
    var client: NonBlockingFileIOClient!
    var fileHandle: NIOFileHandle!
    var fileName: String!
    var repo: TestRepo!
    
    func setupTestFile() -> NIOFileHandle {
        var fileHandle: NIOFileHandle!
        XCTAssertNoThrow(
            fileHandle = try NIOFileHandle(path: self.fileName,
                                                mode: [ .read, .write ],
                                                flags: .allowFileCreation(posixMode: 0o600))
        )
        var buffer = ByteBufferAllocator().buffer(capacity: FileRepoTests.RecordSize * Self.Capacity)
        (0..<Self.Capacity).forEach { i in
            let testString = "String \(i)"
            buffer.writeNullTerminatedString(testString)
            assert(testString.count < 100)
            buffer.writeBytes(Array(repeating: 0, count: FileRepoTests.RecordSize - testString.count - 1))
        }
        
        XCTAssertNoThrow(
            try self.client.write(fileHandle: fileHandle,
                                  toOffset: 0,
                                  buffer: buffer,
                                  eventLoop: self.eventLoop).wait()
        )

        return fileHandle
    }
    
    override func setUp() {
        self.fileName = "/tmp/filerepo_\(UUID().uuidString)"
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.threadPool = .init(numberOfThreads: 2)
        self.threadPool.start()
        self.client = NonBlockingFileIOClient.live(self.threadPool)
        self.eventLoop = self.eventLoopGroup.next()
        self.fileHandle = self.setupTestFile()
        self.repo = TestRepo(allocator: ByteBufferAllocator(),
                             nioFileHandle: self.fileHandle,
                             nonBlockingFileIO: self.client,
                             eventLoop: self.eventLoop)
        XCTAssertNoThrow(try self.repo.sync().wait())
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.repo.close().wait())
        self.repo = nil
//        XCTAssertNoThrow(try self.client.close(fileHandle: self.fileHandle,
//                                               eventLoop: self.eventLoop).wait())
        #if canImport(Foundation)
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: self.fileName))
        #endif
        XCTAssertNoThrow(try self.threadPool.syncShutdownGracefully())
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
        self.threadPool = nil
        self.eventLoopGroup = nil
        self.eventLoop = nil
        self.client = nil
        self.fileHandle = nil
        self.fileName = nil
    }
    
    class TestRepo: FileRepo {
        func fileDecode(id: Int, buffer: inout ByteBuffer) throws -> Model {
            var copy = buffer
            guard let string = copy.readNullTerminatedString()
            else { throw File.Error.readError(message: "Cannot read string", event: #function) }
            
            return .init(id: id, value: string)
        }
        
        func fileEncode(_ row: Model, buffer: inout ByteBuffer) throws {
            guard row.value.count < 100
            else { throw File.Error.illegalArgument }
            
            buffer.writeNullTerminatedString(row.value)
        }
        
        let allocator: ByteBufferAllocator
        let nioFileHandle: NIOFileHandle
        let nonBlockingFileIO: NonBlockingFileIOClient
        let eventLoop: EventLoop
        let offset = 0
        let recordSize: Int = FileRepoTests.RecordSize
        public struct Model: Identifiable {
            let id: Int
            let value: String
        }
        
        init(allocator: ByteBufferAllocator,
             nioFileHandle: NIOFileHandle,
             nonBlockingFileIO: NonBlockingFileIOClient,
             eventLoop: EventLoop) {
            self.allocator = allocator
            self.nioFileHandle = nioFileHandle
            self.nonBlockingFileIO = nonBlockingFileIO
            self.eventLoop = eventLoop
        }
    }
    
    func testFindRecords() {
        var record: TestRepo.Model!
        
        XCTAssertNoThrow(
            try (0..<Self.Capacity).forEach { i in
                record = try self.repo.find(id: i).wait()
                XCTAssertEqual(record.value, "String \(i)")
            }
        )
    }
    
    func testReadFailOffTheEnd() {
        XCTAssertThrowsError(
            try self.repo.find(id: Self.Capacity).wait()
        )
    }
    
    func testFindFrom() {
        var records: [TestRepo.Model]!
        XCTAssertNoThrow(
            records = try self.repo.find(from: 1).wait()
        )
        XCTAssertEqual(records.count, Self.Capacity - 1)
        (1..<Self.Capacity).forEach {
            XCTAssertEqual(records[$0 - 1].id, $0)
            XCTAssertEqual(records[$0 - 1].value, "String \($0)")
        }
    }
    
    func testFindFromThroughFail() {
        XCTAssertThrowsError(
            try self.repo.find(from: 1, through: .max).wait()
        )
    }
    
    func testFindFromThroughFail2() {
        XCTAssertThrowsError(
            try self.repo.find(from: 10, through: 9).wait()
        )
    }
    
    func testFindFromFail() {
        XCTAssertThrowsError(
            try self.repo.find(from: .max).wait()
        )
    }
    
    func testAppend() {
        let appendString = "Append String"
        let model = TestRepo.Model(id: Self.Capacity, value: appendString)
        XCTAssertNoThrow(try self.repo.append([model]).wait())
        XCTAssertNoThrow(try self.repo.sync().wait())
        
        guard let last = try? self.repo.find(from: 0).wait().last
        else { XCTFail(); return }
        
        XCTAssertEqual(last.id, Self.Capacity)
        XCTAssertEqual(last.value, appendString)
    }
    
    func testAppendFail() {
        let model = TestRepo.Model(id: .max, value: "fail")
        XCTAssertThrowsError(try self.repo.append([model]).wait())
    }
    
    func testOverwrite() {
        let model = TestRepo.Model(id: 100, value: "Overwrite")
        XCTAssertNoThrow(try self.repo.write(model).wait())
        XCTAssertNoThrow(try self.repo.sync().wait())
        XCTAssertNoThrow(XCTAssertEqual(try self.repo.find(id: 100).wait().value, "Overwrite"))
    }
    
    func testSkipOverwrite() {
        let model = TestRepo.Model(id: Self.Capacity + 1, value: "Skip")
        XCTAssertNoThrow(try self.repo.write(model).wait())
        XCTAssertNoThrow(try self.repo.sync().wait())
        XCTAssertNoThrow(XCTAssert(try self.repo.find(id: Self.Capacity).wait().value.isEmpty))
    }
    
    func testCount() {
        XCTAssertNoThrow(XCTAssertEqual(try self.repo.count().wait(), Self.Capacity))
    }
    
    func testSearch() {
        XCTAssertNoThrow(try self.repo.binarySearch(comparable: "String 232",
                                                    left: 0,
                                                    right: Self.Capacity - 1,
                                                    selector: \.value).wait())
        XCTAssertNoThrow(try self.repo.binarySearch(comparable: "String 0",
                                                    left: 0,
                                                    right: 0,
                                                    selector: \.value).wait())
        XCTAssertNoThrow(try self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                                                    left: Self.Capacity - 1,
                                                    right: Self.Capacity - 1,
                                                    selector: \.value).wait())
    }
    
    func testSearchFail() {
        XCTAssertThrowsError(try self.repo.binarySearch(comparable: "String 232",
                                                        left: 233,
                                                        right: Self.Capacity - 1,
                                                        selector: \.value).wait())
        XCTAssertThrowsError(try self.repo.binarySearch(comparable: "String",
                                                        left: 0,
                                                        right: Self.Capacity - 1,
                                                        selector: \.value).wait())
        XCTAssertThrowsError(try self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                                                        left: Self.Capacity,
                                                        right: Self.Capacity - 1,
                                                        selector: \.value).wait())
        XCTAssertThrowsError(try self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                                                        left: Self.Capacity - 1,
                                                        right: Self.Capacity,
                                                        selector: \.value).wait())
    }
    
    func testSearchPromise232() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String 232",
                               left: 0, right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertNoThrow(try promise.futureResult.wait())
    }
    
    func testSearchPromise0() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String 0",
                               left: 0, right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertNoThrow(try promise.futureResult.wait())

    }

    func testSearchPromiseLast() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                               left: Self.Capacity - 1,
                               right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertNoThrow(try promise.futureResult.wait())
    }
    
    func testSearchPromise233Fail() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String 232",
                               left: 233,
                               right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertThrowsError(try promise.futureResult.wait())
    }

    func testSearchPromiseStringFail() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String",
                               left: 233,
                               right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertThrowsError(try promise.futureResult.wait())
    }
    
    func testSearchPromiseOffByOneLeftFail() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                               left: Self.Capacity,
                               right: Self.Capacity - 1,
                               promise: promise,
                               selector: \.value)
        XCTAssertThrowsError(try promise.futureResult.wait())
    }

    func testSearchPromiseOffByOneRightFail() {
        let promise = self.eventLoop.makePromise(of: TestRepo.Model.self)
        self.repo.binarySearch(comparable: "String \(Self.Capacity - 1)",
                               left: Self.Capacity - 1,
                               right: Self.Capacity,
                               promise: promise,
                               selector: \.value)
        XCTAssertThrowsError(try promise.futureResult.wait())
    }

    func testDelete() {
        XCTAssertNoThrow(try self.repo.delete(from: 100).wait())
        XCTAssertThrowsError(try self.repo.find(id: 100).wait())
        XCTAssertNoThrow(try self.repo.find(id: 99).wait())
    }
}
