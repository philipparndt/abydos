import Foundation
import Testing
@testable import AbydosKit

/// Reading a POM.
struct MavenProjectTests {
	private func parse(_ text: String, path: String = "/p/app/pom.xml") -> MavenProject? {
		MavenProject.parse(Data(text.utf8), path: URL(fileURLWithPath: path))
	}

	private let springBoot = """
	<?xml version="1.0" encoding="UTF-8"?>
	<project xmlns="http://maven.apache.org/POM/4.0.0">
		<modelVersion>4.0.0</modelVersion>
		<parent>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-parent</artifactId>
			<version>3.2.0</version>
		</parent>
		<artifactId>api</artifactId>
		<version>1.4.0</version>
		<name>The API</name>
		<properties>
			<java.version>21</java.version>
			<start-class>com.example.api.Server</start-class>
		</properties>
		<dependencies>
			<dependency>
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-starter-web</artifactId>
			</dependency>
		</dependencies>
		<build>
			<plugins>
				<plugin>
					<groupId>org.springframework.boot</groupId>
					<artifactId>spring-boot-maven-plugin</artifactId>
				</plugin>
			</plugins>
		</build>
	</project>
	"""

	@Test func readsWhatTheModuleIs() throws {
		let project = try #require(parse(springBoot))
		#expect(project.artifactId == "api")
		#expect(project.version == "1.4.0")
		#expect(project.name == "The API")
		#expect(project.packaging == "jar")
		#expect(project.dependencies == ["spring-boot-starter-web"])
		#expect(project.plugins == ["spring-boot-maven-plugin"])
		#expect(project.isSpringBoot)
	}

	/// A module states neither group nor version and takes both from its parent.
	@Test func fallsBackToTheParentForGroupAndVersion() throws {
		let project = try #require(parse("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<parent>
				<groupId>com.example</groupId>
				<artifactId>platform</artifactId>
				<version>2.0.0</version>
			</parent>
			<artifactId>worker</artifactId>
		</project>
		"""))
		#expect(project.groupId == "com.example")
		#expect(project.version == "2.0.0")
	}

	@Test func readsAnAggregatorsModules() throws {
		let project = try #require(parse("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<groupId>com.example</groupId>
			<artifactId>platform</artifactId>
			<version>1.0.0</version>
			<packaging>pom</packaging>
			<modules>
				<module>api</module>
				<module>worker</module>
			</modules>
		</project>
		"""))
		#expect(project.isAggregator)
		#expect(project.modules == ["api", "worker"])
		// Nothing to run in a module that only lists other modules.
		#expect(!project.goals.contains { $0.name == "verify" })
	}

	/// Spring Boot's property is one of three ways a build says which class to
	/// start.
	@Test func findsTheMainClassThreeWays() throws {
		#expect(try #require(parse(springBoot)).mainClass == "com.example.api.Server")

		let exec = try #require(parse("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<artifactId>tool</artifactId>
			<build><plugins><plugin>
				<artifactId>exec-maven-plugin</artifactId>
				<configuration><mainClass>com.example.Tool</mainClass></configuration>
			</plugin></plugins></build>
		</project>
		"""))
		#expect(exec.mainClass == "com.example.Tool")

		let property = try #require(parse("""
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<artifactId>tool</artifactId>
			<properties><mainClass>com.example.Other</mainClass></properties>
		</project>
		"""))
		#expect(property.mainClass == "com.example.Other")
	}

	/// A file that is XML but not a POM is not one, and neither is a broken one.
	@Test func refusesWhatIsNotAPOM() {
		#expect(parse("<beans><bean id=\"x\"/></beans>") == nil)
		#expect(parse("not xml at all") == nil)
		// Without an artefact id there is nothing to call the module.
		#expect(parse("<project xmlns=\"http://maven.apache.org/POM/4.0.0\"><groupId>x</groupId></project>") == nil)
	}

	@Test func namesTheJarMavenWouldBuild() throws {
		let project = try #require(parse(springBoot))
		#expect(project.artefactName == "api-1.4.0.jar")
		#expect(project.artefactPath.path == "/p/app/target/api-1.4.0.jar")
	}

	/// The wrapper is the point: a project that pins its Maven version means it.
	@Test func prefersTheWrapper() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let module = root.appendingPathComponent("api")
		try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)

		#expect(MavenProject.executable(for: module, root: root) == "mvn")

		let wrapper = try JavaTestDirectory.write(
			"#!/bin/sh\n", to: root.appendingPathComponent("mvnw"), executable: true
		)
		// Found from the module, though it lives at the root of the build.
		#expect(MavenProject.executable(for: module, root: root) == wrapper.path)
	}

	@Test func listsWhatIsWorthNavigatingTo() throws {
		let project = try #require(parse(springBoot))
		let symbols = MavenProject.symbols(
			of: project, in: springBoot, at: URL(fileURLWithPath: "/p/app/pom.xml")
		)
		let names = symbols.map(\.name)
		#expect(names.contains("api"))
		#expect(names.contains("spring-boot-starter-web"))
		#expect(names.contains("spring-boot-maven-plugin"))
		#expect(names.contains("start-class"))

		// The line is the one the thing is written on, not the top of the file.
		let dependency = try #require(symbols.first { $0.name == "spring-boot-starter-web" })
		let line = springBoot.components(separatedBy: "\n")[dependency.location.range.start.line]
		#expect(line.contains("spring-boot-starter-web"))
	}
}

/// An empty directory of its own, for a test that needs real files.
enum JavaTestDirectory {
	static func make() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-java-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	/// Writes a file, making the directories above it.
	@discardableResult
	static func write(_ contents: String, to url: URL, executable: Bool = false) throws -> URL {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try Data(contents.utf8).write(to: url)
		if executable {
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
		}
		return url
	}
}
