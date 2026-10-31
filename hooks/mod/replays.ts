/**
 * Each raw MobileBuildMCP capture of the test bed as the mod gets it, the joined text of the result's content, and what
 * `xcrew report` answers for it, with xcresulttool's answers about its result bundle read from the test bed. Written
 * by scripts/replays.sh; TestbedReplayTests holds each answer to the CLI and to MobileBuildMCP's own counts.
 */
export const replays = {
  "profile" : {
    "isError" : false,
    "report" : {
      "bundle" : "/testbed/user/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/result-bundles/test_sim_2026-10-31T02-59-00-759Z_pid20778_edcccb69.xcresult",
      "detail" : "1 passed",
      "durationMs" : 4400,
      "failures" : [

      ],
      "notes" : [

      ],
      "ok" : true,
      "tests" : 1
    },
    "text" : "\n🧪 Test\n\n✅ 1 test passed, 0 failed, 0 skipped (⏱️ 4.4s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/\n         ├── logs/test_sim_2026-10-31T02-59-00-758Z_pid20778_08846489.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T02-59-00-759Z_pid20778_edcccb69.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T02-59-00-759Z_pid20778_b2544e1d.xctestproducts — Test Products\n"
  },
  "serial" : {
    "isError" : true,
    "report" : {
      "bundle" : "/testbed/user/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/result-bundles/test_sim_2026-10-31T02-58-33-451Z_pid19405_dd194716.xcresult",
      "detail" : "2 of 4 failed · ProbeTests/testFails",
      "durationMs" : 14200,
      "failures" : [
        {
          "isTest" : true,
          "message" : "XCTAssertEqual failed: (\"Hello, Ada\") is not equal to (\"Hi, Ada\")",
          "target" : "FeatureTests",
          "title" : "ProbeTests/testFails",
          "where" : "ProbeTests.swift:11"
        },
        {
          "isTest" : true,
          "message" : "XCTAssertEqual failed: (\"1\") is not equal to (\"0\") - run 1 is odd",
          "target" : "FeatureTests",
          "title" : "ProbeTests/testFlaky",
          "where" : "ProbeTests.swift:19"
        }
      ],
      "notes" : [
        "xcrew: 1 test also ran as an expected failure (XCTExpectFailure): ProbeTests/testExpectedFailure(). They count as neither passed nor failed in the result: 5 tests ran in all."
      ],
      "ok" : false,
      "result" : "\n🧪 Test\n\nWarnings (1):\n\n  ⚠ initialization of immutable value 'unused' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]\n    /testbed/field/Modules/Feature/Sources/Legacy.swift:3\n\nTest Failures (4):\n\n  ✗ ProbeTests / testFails: XCTAssertEqual failed: (\"Hello, Ada\") is not equal to (\"Hi, Ada\")\n    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:11\n\n  ✗ ProbeTests / testFails(): XCTAssertEqual failed: (\"Hello, Ada\") is not equal to (\"Hi, Ada\")\n\n  ✗ ProbeTests / testFlaky: XCTAssertEqual failed: (\"1\") is not equal to (\"0\") - run 1 is odd\n    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:19\n\n  ✗ ProbeTests / testFlaky(): XCTAssertEqual failed: (\"1\") is not equal to (\"0\") - run 1 is odd\n  ⏭️ ProbeTests/testSkipped() (0.014s)\n      skipped: waits for the farewell screen\n\n❌ 2 tests failed, 1 passed, 1 skipped (⏱️ 14.2s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/\n         ├── logs/test_sim_2026-10-31T02-58-33-450Z_pid19405_1183ca26.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T02-58-33-451Z_pid19405_dd194716.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T02-58-33-451Z_pid19405_f2831d6c.xctestproducts — Test Products\n",
      "tests" : 4
    },
    "text" : "\n🧪 Test\n\nWarnings (1):\n\n  ⚠ initialization of immutable value 'unused' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]\n    /testbed/field/Modules/Feature/Sources/Legacy.swift:3\n\nTest Failures (4):\n\n  ✗ ProbeTests / testFails: XCTAssertEqual failed: (\"Hello, Ada\") is not equal to (\"Hi, Ada\")\n    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:11\n\n  ✗ ProbeTests / testFails(): XCTAssertEqual failed: (\"Hello, Ada\") is not equal to (\"Hi, Ada\")\n\n  ✗ ProbeTests / testFlaky: XCTAssertEqual failed: (\"1\") is not equal to (\"0\") - run 1 is odd\n    /testbed/field/Modules/Feature/Tests/ProbeTests.swift:19\n\n  ✗ ProbeTests / testFlaky(): XCTAssertEqual failed: (\"1\") is not equal to (\"0\") - run 1 is odd\n\n❌ 2 tests failed, 1 passed, 1 skipped (⏱️ 14.2s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/\n         ├── logs/test_sim_2026-10-31T02-58-33-450Z_pid19405_1183ca26.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T02-58-33-451Z_pid19405_dd194716.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T02-58-33-451Z_pid19405_f2831d6c.xctestproducts — Test Products\n"
  },
  "shapes" : {
    "isError" : true,
    "report" : {
      "bundle" : "/testbed/user/Library/Developer/MobileBuildMCP/workspaces/swift-testing-3298874e7ebf/result-bundles/test_sim_2026-10-31T03-19-02-491Z_pid59004_a5d039b9.xcresult",
      "detail" : "1 of 5 failed · ShapesTests/fails",
      "durationMs" : 15200,
      "failures" : [
        {
          "isTest" : true,
          "message" : "Expectation failed: Kit.name == \"Other\"",
          "target" : "KitTests",
          "title" : "ShapesTests/fails",
          "where" : "ShapesTests.swift:10"
        }
      ],
      "notes" : [
        "xcrew: 1 test also ran with a known issue (withKnownIssue): ShapesTests/knownIssue(). They count as neither passed nor failed in the result: 6 tests ran in all."
      ],
      "ok" : false,
      "result" : "\n🧪 Test\n\nDiscovered 6 test(s):\n   KitTests/ShapesTests/fails\n   KitTests/ShapesTests/knownIssue\n   KitTests/ShapesTests/parameterised\n   KitTests/ShapesTests/passes\n   KitTests/ShapesTests/skipped\n   KitTests/ShapesTests/waits\n\nTest Failures (1):\n\n  ✗ ShapesTests / fails(): Expectation failed: Kit.name == \"Other\"\n    /testbed/swift-testing/KitTests/ShapesTests.swift:10\n    Kit.name → \"Kit\": the name is Kit\n  ⏭️ ShapesTests/skipped() (0.000s)\n      skipped: skipped on purpose\n\n❌ 1 test failed, 3 passed, 1 skipped (⏱️ 15.2s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/swift-testing-3298874e7ebf/\n         ├── logs/test_sim_2026-10-31T03-19-02-491Z_pid59004_51632903.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T03-19-02-491Z_pid59004_a5d039b9.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T03-19-02-491Z_pid59004_eeffdb47.xctestproducts — Test Products\n",
      "tests" : 5
    },
    "text" : "\n🧪 Test\n\nDiscovered 6 test(s):\n   KitTests/ShapesTests/fails\n   KitTests/ShapesTests/knownIssue\n   KitTests/ShapesTests/parameterised\n   KitTests/ShapesTests/passes\n   KitTests/ShapesTests/skipped\n   KitTests/ShapesTests/waits\n\nTest Failures (1):\n\n  ✗ ShapesTests / fails(): Expectation failed: Kit.name == \"Other\"\n    Kit.name → \"Kit\": the name is Kit\n\n❌ 1 test failed, 3 passed, 1 skipped (⏱️ 15.2s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/swift-testing-3298874e7ebf/\n         ├── logs/test_sim_2026-10-31T03-19-02-491Z_pid59004_51632903.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T03-19-02-491Z_pid59004_a5d039b9.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T03-19-02-491Z_pid59004_eeffdb47.xctestproducts — Test Products\n"
  },
  "swift-testing" : {
    "isError" : false,
    "report" : {
      "bundle" : "/testbed/user/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/result-bundles/test_sim_2026-10-31T02-58-52-105Z_pid20279_8eddb088.xcresult",
      "detail" : "1 passed",
      "durationMs" : 7200,
      "failures" : [

      ],
      "notes" : [

      ],
      "ok" : true,
      "tests" : 1
    },
    "text" : "\n🧪 Test\n\n✅ 1 test passed, 0 failed, 0 skipped (⏱️ 7.2s)\n  └ Files:\n     └── ~/Library/Developer/MobileBuildMCP/workspaces/field-3d32f8cd53a2/\n         ├── logs/test_sim_2026-10-31T02-58-52-105Z_pid20279_dfc11d40.log — Build Logs\n         ├── result-bundles/test_sim_2026-10-31T02-58-52-105Z_pid20279_8eddb088.xcresult — Result Bundle\n         └── test-products/test_sim_2026-10-31T02-58-52-105Z_pid20279_32ef7fd1.xctestproducts — Test Products\n"
  }
}
