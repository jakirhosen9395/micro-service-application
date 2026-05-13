package com.microapp.calculator.health;

import com.fasterxml.jackson.annotation.JsonInclude;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record DependencyResult(
        String status,
        double latencyMs,
        String errorCode
) {
    public static DependencyResult ok(double latencyMs) {
        return new DependencyResult("ok", round(latencyMs), null);
    }

    public static DependencyResult down(double latencyMs, String errorCode) {
        return new DependencyResult("down", round(latencyMs), errorCode);
    }

    private static double round(double value) {
        return Math.round(value * 10.0) / 10.0;
    }
}
