# Compiled to bytecode: requires JVM at runtime. Multi-stage splits JDK (build) from JRE (run).
# For dependency-heavy projects: copy pom.xml first and resolve deps as a cached layer,
# then copy src. Cache invalidates only when pom.xml changes, not on every source edit.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn package -q -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/app-1.0.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
