package com.microapp.calculator.http;

import com.microapp.calculator.config.AppProperties;
import com.microapp.calculator.health.HealthResponse;
import com.microapp.calculator.health.HealthService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class SystemController {
    private final AppProperties props;
    private final HealthService healthService;

    public SystemController(AppProperties props, HealthService healthService) {
        this.props = props;
        this.healthService = healthService;
    }

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
                "status", "ok",
                "message", props.getServiceName() + " is running",
                "service", Map.of(
                        "name", props.getServiceName(),
                        "env", props.getEnvironment(),
                        "version", props.getVersion()
                )
        );
    }

    @GetMapping("/health")
    public ResponseEntity<HealthResponse> health() {
        HealthResponse response = healthService.health();
        return ResponseEntity.status("ok".equals(response.status()) ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE).body(response);
    }

    @GetMapping(value = "/docs", produces = MediaType.TEXT_HTML_VALUE)
    public String docs() {
        return DocsHtml.html(props);
    }
}
