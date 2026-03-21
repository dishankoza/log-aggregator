package com.example.tracing;

import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@RestController
public class TraceController {

    private final RestTemplate restTemplate;
    private final String cppServiceUrl;

    public TraceController(RestTemplate restTemplate,
                           @Value("${cpp.service.url:http://localhost:8082/}") String cppServiceUrl) {
        this.restTemplate = restTemplate;
        this.cppServiceUrl = cppServiceUrl;
    }

    @GetMapping("/")
    public Map<String, Object> callCpp() {
        ResponseEntity<String> response = restTemplate.getForEntity(cppServiceUrl, String.class);

        return Map.of(
                "service", "java-service",
                "downstreamStatus", response.getStatusCode().value(),
                "downstreamBody", response.getBody()
        );
    }
}
