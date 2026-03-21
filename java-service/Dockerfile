FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /app

COPY pom.xml ./
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /app/target/java-service-0.0.1-SNAPSHOT.jar /app/java-service.jar
COPY opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

EXPOSE 8081

ENTRYPOINT ["java","-javaagent:/app/opentelemetry-javaagent.jar","-jar","/app/java-service.jar"]
