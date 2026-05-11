package com.microapp.calculator.http;

import com.microapp.calculator.domain.CalculationRequest;
import com.microapp.calculator.domain.CalculatorApplicationService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/calculator")
public class CalculatorController {
    private final CalculatorApplicationService service;

    public CalculatorController(CalculatorApplicationService service) {
        this.service = service;
    }

    @GetMapping("/operations")
    public ResponseEntity<ApiResponse<?>> operations() {
        return ResponseEntity.ok(ApiResponse.ok("operations loaded", service.operations()));
    }

    @PostMapping("/calculate")
    public ResponseEntity<ApiResponse<?>> calculate(@Valid @RequestBody CalculationRequest request) {
        return ResponseEntity.ok(ApiResponse.ok("calculation completed", service.calculate(request)));
    }

    @GetMapping("/history")
    public ResponseEntity<ApiResponse<?>> history(@RequestParam(name = "limit", required = false, defaultValue = "0") int limit) {
        return ResponseEntity.ok(ApiResponse.ok("history loaded", service.historyForCurrentUser(limit)));
    }

    @GetMapping("/history/{userId}")
    public ResponseEntity<ApiResponse<?>> historyForUser(@PathVariable String userId, @RequestParam(name = "limit", required = false, defaultValue = "0") int limit) {
        return ResponseEntity.ok(ApiResponse.ok("history loaded", service.history(userId, limit)));
    }

    @GetMapping("/records/{calculationId}")
    public ResponseEntity<ApiResponse<?>> record(@PathVariable String calculationId) {
        return ResponseEntity.ok(ApiResponse.ok("calculation record loaded", service.record(calculationId)));
    }

    @DeleteMapping("/history")
    public ResponseEntity<ApiResponse<?>> clearHistory() {
        return ResponseEntity.ok(ApiResponse.ok("history cleared", service.clearHistory()));
    }
}
