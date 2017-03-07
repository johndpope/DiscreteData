import PackageDescription

let package = Package(
    name: "DiscreteData",
    dependencies: [
        .Package(url: "https://github.com/michael-yuji/CKit.git", majorVersion: 0)
    ]
)
