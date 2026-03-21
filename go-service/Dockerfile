FROM golang:1.25 AS build

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /bin/go-service .

FROM gcr.io/distroless/base-debian12

COPY --from=build /bin/go-service /go-service

EXPOSE 8080

ENTRYPOINT ["/go-service"]
