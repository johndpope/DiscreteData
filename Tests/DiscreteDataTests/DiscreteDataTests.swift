import XCTest
@testable import DiscreteData

class DiscreteDataTests: XCTestCase {
    fileprivate let arr1: [Int8] = [1, 2, 3, 4, 5, 6]
    fileprivate let arr2: [Int8] = [11, 12, 13, 14, 15, 16]
    fileprivate let arr3: [Int8] = [21, 22, 23, 24, 25, 26]

    func testInsert() {
        let data = DiscreteData._FragmentContainer(buffer: arr1, length: arr1.count)
        let adata = DiscreteData._FragmentContainer(buffer: arr2, length: arr2.count)
        data.insert(data: adata, at: 4)

        let out = [Int8](repeating: 0, count: arr1.count + arr2.count)
        data.getBytes(from: 0, length: arr1.count + arr2.count, to: UnsafeMutableRawPointer(mutating: out))

        XCTAssertEqual(out, [1, 2, 3, 4, 11, 12, 13, 14, 15, 16, 5, 6])
    }


    func testAppend() {
        let data = DiscreteData._FragmentContainer(buffer: arr1, length: arr1.count)
        let adata = DiscreteData._FragmentContainer(buffer: arr2, length: arr2.count)
        data.append(data: adata)

        let out = [Int8](repeating: 0, count: arr1.count + arr2.count)
        data.getBytes(from: 0, length: arr1.count + arr2.count, to: UnsafeMutableRawPointer(mutating: out))

        XCTAssertEqual(out, [1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16])
    }

    func testSubdataOneFragment() {
        let data = DiscreteData._FragmentContainer(buffer: arr1, length: arr1.count)
        let subb = data.subdata(from: 2, len: 2)

        let out = [Int8](repeating: 0, count: subb.length)
        subb.getBytes(from: 0, length: subb.length, to: UnsafeMutableRawPointer(mutating: out))

        XCTAssertEqual(out, [3, 4])
    }

    func testSubdataTwoFragments() {
        let fragment1 = DataFragment(buffer: arr1, length: arr1.count)
        let fragment2 = DataFragment(buffer: arr2, length: arr2.count)

        let data = DiscreteData._FragmentContainer(fragments: [fragment1, fragment2])

        let subb = data.subdata(from: arr1.count - 2, len: 4)

        let out = [Int8](repeating: 0, count: subb.length)
        subb.getBytes(from: 0, length: subb.length, to: UnsafeMutableRawPointer(mutating: out))

        XCTAssertEqual(out, [5, 6, 11, 12])
    }

    func testSubdataThreeFragments() {
        let fragment1 = DataFragment(buffer: arr1, length: arr1.count)
        let fragment2 = DataFragment(buffer: arr2, length: arr2.count)
        let fragment3 = DataFragment(buffer: arr3, length: arr3.count)

        let data = DiscreteData._FragmentContainer(fragments: [fragment1, fragment2, fragment3])

        let start = arr1.count - 2
        let length = 2 + arr2.count + 2
        let subb = data.subdata(from: start, len: length)

        let out = [Int8](repeating: 0, count: subb.length)
        subb.getBytes(from: 0, length: subb.length, to: UnsafeMutableRawPointer(mutating: out))

        XCTAssertEqual(out, [5, 6, 11, 12, 13, 14, 15, 16, 21, 22])
    }

    static var allTests : [(String, (DiscreteDataTests) -> () throws -> Void)] {
        return [
            ("insert", testInsert),
            ("append", testAppend),
            ("subdata one fragment", testSubdataOneFragment),
            ("subdata two fragments", testSubdataTwoFragments),
            ("subdata three fragments", testSubdataThreeFragments)
        ]
    }
}
