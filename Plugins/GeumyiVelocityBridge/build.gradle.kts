plugins {
    java
}

group = "kr.geumyi"
version = "0.1.0-canary-dev"

repositories {
    maven("https://repo.papermc.io/repository/maven-public/")
    mavenCentral()
}

// Operator supplied read-only JAR fingerprints: all three instances have
// manifest version hint 4.2.0 and identical SHA-256. This is a compile
// baseline, NOT approval to install or proof of live binary compatibility.
// CI also compiles against 4.2.1-SNAPSHOT as a forward-compatibility check.
val velocityApiVersion = providers.gradleProperty("velocityApiVersion").orElse("4.2.0").get()

dependencies {
    compileOnly("com.velocitypowered:velocity-api:$velocityApiVersion")
    annotationProcessor("com.velocitypowered:velocity-api:$velocityApiVersion")
    testImplementation("com.velocitypowered:velocity-api:$velocityApiVersion")
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

tasks.test {
    useJUnitPlatform()
}
