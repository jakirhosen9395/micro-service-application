package com.microservice.todo.dto;

import java.util.List;

public record TodoPageData(
        List<TodoResponse> items,
        int page,
        int size,
        long totalItems,
        int totalPages
) {}
