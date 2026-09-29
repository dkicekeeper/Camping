// swift-tools-version: 6.1
import PackageDescription

// Модули приложения Dalada. Зависимости идут только сверху вниз:
// AppFeature → (DaladaUI, MapEngine, Backend, Sync → Persistence) → DaladaCore.
// См. docs/03-architecture/01-ios-app.md.
let package = Package(
    name: "DaladaKit",
    defaultLocalization: "ru",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        // Приложению нужен только AppFeature. Остальные продукты — чтобы Xcode создал общую схему
        // `DaladaKit-Package`, которая собирает всё и запускает все тесты (так делает CI).
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Sync", targets: ["Sync"]),
    ],
    dependencies: [
        // DesignKit без тегов — закрепляем на коммите.
        .package(url: "https://github.com/dkicekeeper/DesignKit", revision: "b87b25055580449647c3f37601561e47f593a6b1"),
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", from: "6.31.0"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.3"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        // Доменные типы и конфигурация. Без UI и сторонних зависимостей.
        .target(name: "DaladaCore"),

        // Компоненты приложения поверх DesignKit.
        .target(
            name: "DaladaUI",
            dependencies: [
                "DaladaCore",
                .product(name: "DesignKit", package: "DesignKit"),
            ]
        ),

        // Обёртка над MapLibre. Фичи не импортируют MapLibre напрямую.
        .target(
            name: "MapEngine",
            dependencies: [
                "DaladaCore",
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
            ]
        ),

        // Обёртка над supabase-swift. Фичи не импортируют Supabase напрямую.
        .target(
            name: "Backend",
            dependencies: [
                "DaladaCore",
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),

        // Локальная база (GRDB): офлайн-очередь и кэш. Без UI и сети.
        .target(
            name: "Persistence",
            dependencies: [
                "DaladaCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // Отправка офлайн-очереди с повторами. Сервер — через протокол `CheckinSending`.
        .target(
            name: "Sync",
            dependencies: ["DaladaCore", "Persistence"]
        ),

        // Вкладки, навигация, экраны.
        .target(
            name: "AppFeature",
            dependencies: [
                "DaladaCore",
                "DaladaUI",
                "MapEngine",
                "Backend",
                "Persistence",
                "Sync",
                .product(name: "DesignKit", package: "DesignKit"),
            ]
        ),

        .testTarget(name: "DaladaCoreTests", dependencies: ["DaladaCore"]),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "SyncTests", dependencies: ["Sync", "Persistence"]),
    ],
    swiftLanguageModes: [.v6]
)
