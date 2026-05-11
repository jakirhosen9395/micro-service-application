package com.microapp.calculator.domain;

import java.math.BigDecimal;
import java.util.List;

public record CalculationRequest(
        String operation,
        List<BigDecimal> operands,
        String expression
) {
}
