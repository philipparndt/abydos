import Foundation
import Testing
@testable import AbydosKit

/// What a Java project offers to run, and how it is built for a pod.
struct JavaRunConfigurationTests {
	/// A Maven module: its goals, and the class it can start.
	@Test func discoversMavenGoalsAndMainClasses() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<groupId>com.example</groupId>
			<artifactId>api</artifactId>
			<version>1.0.0</version>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		package com.example.api;
		public class Server {
			public static void main(String[] args) {
			}
		}
		""", to: root.appendingPathComponent("src/main/java/com/example/api/Server.java"))

		let found = RunConfigurationDiscovery.discover(in: root)

		let goals = found.filter { $0.source == .maven }
		#expect(goals.map(\.name).contains("mvn package"))
		#expect(goals.map(\.name).contains("mvn test"))
		#expect(goals.first?.executable == "mvn")

		// The class, run through the exec plugin because nothing in the build
		// says how to start it.
		let main = try #require(found.first { $0.source == .javaMain })
		#expect(main.name == "run Server")
		#expect(main.mainClass == "com.example.api.Server")
		#expect(main.arguments.contains("-Dexec.mainClass=com.example.api.Server"))
		#expect(main.line == 3)
		// And that is the one thing here a debugger can start.
		#expect(main.isDebuggable)
		#expect(goals.allSatisfy { !$0.isDebuggable })
	}

	/// Spring Boot's plugin starts the application itself, and does it better
	/// than exec:java would.
	@Test func prefersSpringBootsOwnGoal() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<artifactId>api</artifactId>
			<build><plugins><plugin>
				<artifactId>spring-boot-maven-plugin</artifactId>
			</plugin></plugins></build>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		package com.example;
		public class App {
			public static void main(String[] args) {}
		}
		""", to: root.appendingPathComponent("src/main/java/com/example/App.java"))

		let found = RunConfigurationDiscovery.discover(in: root)
		#expect(found.contains { $0.name == "mvn spring-boot:run" })
		let main = try #require(found.first { $0.source == .javaMain })
		#expect(main.arguments == ["spring-boot:run"])
	}

	/// A Gradle sub-project is named the way Gradle names it, and run from
	/// where the wrapper is.
	@Test func namesGradleTasksFromTheRootOfTheBuild() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write("#!/bin/sh\n", to: root.appendingPathComponent("gradlew"), executable: true)
		try JavaTestDirectory.write("rootProject.name = 'platform'\ninclude 'api'\n",
		                            to: root.appendingPathComponent("settings.gradle"))
		try JavaTestDirectory.write("plugins {\n id 'application'\n}\n",
		                            to: root.appendingPathComponent("api/build.gradle"))

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .gradle }
		let test = try #require(found.first { $0.name == "gradle test (api)" })
		#expect(test.executable.hasSuffix("/gradlew"))
		#expect(test.arguments == [":api:test"])
		#expect(test.workingDirectory == FilePath.canonical(root))
	}

	/// A Gradle module with neither the application nor the Spring Boot plugin
	/// has no task that starts a class, and inventing one is not this app's
	/// business.
	@Test func offersNoRunForAGradleLibrary() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		try JavaTestDirectory.write("plugins {\n id 'java-library'\n}\n",
		                            to: root.appendingPathComponent("build.gradle"))
		try JavaTestDirectory.write("""
		public class Tool {
			public static void main(String[] args) {}
		}
		""", to: root.appendingPathComponent("src/main/java/Tool.java"))

		let found = RunConfigurationDiscovery.discover(in: root)
		#expect(!found.contains { $0.source == .javaMain })
		#expect(found.contains { $0.name == "gradle build" })
	}

	// MARK: - The pod

	@Test func buildsAJarForThePod() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write("<project/>", to: root.appendingPathComponent("pom.xml"))

		let configuration = LaunchConfiguration(
			name: "in the cluster", type: "java", program: "com.example.api.Server"
		)
		// The temporary directory is `/var/…` and resolves to `/private/var/…`,
		// which is the path the strategy reports.
		#expect(DevPodBuild.strategy(for: configuration, root: root)
			== .maven(directory: FilePath.canonical(root)))
		// A JVM debugs itself, so what the pod needs is a JVM rather than a
		// debugger — and that is a different image.
		#expect(DevPodBuild.debugger(for: configuration, root: root) == .jdwp)
		#expect(DevPodImage.resolved("", for: configuration, root: root)
			== "\(DevPodImage.repository):\(DevPodImage.version)-jvm")
	}

	@Test func recognisesAGradleBuildForThePod() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write("plugins { id 'application' }",
		                            to: root.appendingPathComponent("build.gradle.kts"))

		let configuration = LaunchConfiguration(name: "cluster", type: "java", program: "com.example.App")
		#expect(DevPodBuild.strategy(for: configuration, root: root)
			== .gradle(directory: FilePath.canonical(root)))
	}

	/// The jar to push is the one the build just made — never the sources jar a
	/// publishing project also produces.
	@Test func picksTheRightJar() throws {
		let directory = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: directory) }

		try JavaTestDirectory.write("x", to: directory.appendingPathComponent("api-1.0-sources.jar"))
		try JavaTestDirectory.write("x", to: directory.appendingPathComponent("api-1.0-javadoc.jar"))
		try JavaTestDirectory.write("x", to: directory.appendingPathComponent("api-1.0.jar"))

		let jar = try DevPodBuild.jar(in: directory, what: "Maven")
		#expect(jar.lastPathComponent == "api-1.0.jar")
	}

	@Test func saysSoWhenTheBuildProducedNoJar() throws {
		let directory = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: directory) }

		#expect(throws: DevPodBuild.Failure.self) {
			_ = try DevPodBuild.jar(in: directory, what: "Gradle")
		}
	}
}
