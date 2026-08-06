import Foundation
import Testing
@testable import AbydosKit

/// Reading a Gradle build file.
struct GradleBuildTests {
	private func parse(_ text: String, named name: String = "build.gradle") -> GradleBuild {
		GradleBuild.parse(text, path: URL(fileURLWithPath: "/p/app/\(name)"))
	}

	@Test func readsPluginsFromTheGroovyDSL() {
		let build = parse("""
		plugins {
			id 'java'
			id 'application'
			id 'org.springframework.boot' version '3.2.0'
		}

		application {
			mainClassName = 'com.example.Server'
		}
		""")
		#expect(build.plugins == ["java", "application", "org.springframework.boot"])
		#expect(build.isApplication)
		#expect(build.isSpringBoot)
		#expect(build.mainClass == "com.example.Server")
	}

	@Test func readsPluginsFromTheKotlinDSL() {
		let build = parse("""
		plugins {
			kotlin("jvm") version "2.0.0"
			id("application")
		}

		application {
			mainClass.set("com.example.MainKt")
		}
		""", named: "build.gradle.kts")
		#expect(build.plugins.contains("application"))
		#expect(build.mainClass == "com.example.MainKt")
		#expect(build.isKotlinDSL)
	}

	/// The older spelling, which plenty of builds still use.
	@Test func readsAppliedPlugins() {
		let build = parse("apply plugin: 'java'\napply plugin: 'application'")
		#expect(build.plugins == ["java", "application"])
	}

	@Test func readsTasksInEverySpelling() {
		let build = parse("""
		task hello {
			description 'says hello'
		}
		task copyFiles(type: Copy) {
		}
		tasks.register("integrationTest") {
		}
		tasks.register<Copy>("stage") {
		}
		""")
		#expect(build.tasks.map(\.name) == ["hello", "copyFiles", "integrationTest", "stage"])
		#expect(build.tasks.first?.line == 1)
		#expect(build.tasks.first?.summary == "says hello")
	}

	/// A comment that mentions a task is not a task.
	@Test func ignoresComments() {
		let build = parse("""
		// task ghost {
		/* tasks.register("phantom") */
		task real {
		}
		""")
		#expect(build.tasks.map(\.name) == ["real"])
	}

	@Test func readsIncludesFromASettingsFile() {
		let build = parse("""
		rootProject.name = 'platform'
		include 'api', 'worker'
		include(":tools:cli")
		""", named: "settings.gradle")
		#expect(build.projects == ["api", "worker", "tools:cli"])
	}

	/// The standard tasks are added, and never twice.
	@Test func offersTheTasksSomebodyWouldRun() {
		let application = parse("plugins {\n id 'application'\n}\ntask stage {\n}")
		let names = application.runnableTasks.map(\.name)
		#expect(names.contains("stage"))
		#expect(names.contains("run"))
		#expect(names.contains("test"))
		#expect(names.contains("build"))
		#expect(names.contains("assemble"))
		#expect(Set(names).count == names.count)

		// Spring Boot's own, and no plain `run` — bootRun is what starts it.
		let boot = parse("plugins {\n id 'org.springframework.boot' version '3.2.0'\n}")
		let bootNames = boot.runnableTasks.map(\.name)
		#expect(bootNames.contains("bootRun"))
		#expect(bootNames.contains("bootJar"))
		#expect(!bootNames.contains("run"))
	}

	@Test func prefersTheWrapper() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let module = root.appendingPathComponent("api")
		try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)

		#expect(GradleBuild.executable(for: module, root: root) == "gradle")

		let wrapper = try JavaTestDirectory.write(
			"#!/bin/sh\n", to: root.appendingPathComponent("gradlew"), executable: true
		)
		#expect(GradleBuild.executable(for: module, root: root) == wrapper.path)
	}

	@Test func listsWhatIsWorthNavigatingTo() {
		let text = """
		plugins {
			id 'application'
		}
		task stage {
		}
		"""
		let symbols = GradleBuild.symbols(
			of: parse(text), in: text, at: URL(fileURLWithPath: "/p/app/build.gradle")
		)
		#expect(symbols.map(\.name).contains("stage"))
		#expect(symbols.map(\.name).contains("application"))
		// Line 4 in the file is index 3.
		#expect(symbols.first { $0.name == "stage" }?.location.range.start.line == 3)
	}
}
