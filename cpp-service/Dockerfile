FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends g++ libcurl4-openssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY main.cpp .
RUN g++ -std=c++17 -O2 -o /cpp-service main.cpp -lcurl

EXPOSE 8082

ENTRYPOINT ["/cpp-service"]
