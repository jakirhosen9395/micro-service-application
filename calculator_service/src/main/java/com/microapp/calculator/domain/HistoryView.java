package com.microapp.calculator.domain;

import java.util.List;

public record HistoryView(
        String userId,
        int limit,
        int count,
        List<CalculationView> items,
        String source
) {
}
