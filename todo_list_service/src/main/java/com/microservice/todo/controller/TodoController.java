package com.microservice.todo.controller;

import com.microservice.todo.dto.ApiResponse;
import com.microservice.todo.dto.DeleteTodoData;
import com.microservice.todo.dto.StatusChangeData;
import com.microservice.todo.dto.TodoCreateRequest;
import com.microservice.todo.dto.TodoHistoryData;
import com.microservice.todo.dto.TodoPageData;
import com.microservice.todo.dto.TodoResponse;
import com.microservice.todo.dto.TodoStatusChangeRequest;
import com.microservice.todo.dto.TodoUpdateRequest;
import com.microservice.todo.entity.TodoPriority;
import com.microservice.todo.entity.TodoStatus;
import com.microservice.todo.service.TodoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.time.Instant;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/todos")
@Tag(name = "todos", description = "Authenticated todo create, list, update, status, archive, restore, delete, and history APIs")
@SecurityRequirement(name = "bearerAuth")
public class TodoController {
    private final TodoService todoService;

    public TodoController(TodoService todoService) {
        this.todoService = todoService;
    }

    @PostMapping
    @Operation(summary = "Create a todo", description = "Creates a todo owned by the authenticated JWT subject. Status defaults to PENDING.")
    @ApiResponses({
            @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode = "201", description = "Todo created", content = @Content(schema = @Schema(implementation = ApiResponse.class), examples = @ExampleObject(value = """
                    {"status":"ok","message":"todo created","data":{"id":"todo-uuid","title":"Verify todo_list_service requirements","status":"PENDING","priority":"HIGH"}}
                    """))),
            @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode = "401", description = "Authentication required", content = @Content(examples = @ExampleObject(value = """
                    {"status":"error","message":"Authentication required","error_code":"TODO_UNAUTHORIZED"}
                    """)))
    })
    public ResponseEntity<ApiResponse<TodoResponse>> create(@Valid @RequestBody TodoCreateRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.ok("todo created", todoService.create(request)));
    }

    @GetMapping
    @Operation(summary = "List/search/filter todos")
    public ApiResponse<TodoPageData> list(
            @RequestParam(required = false) TodoStatus status,
            @RequestParam(required = false) TodoPriority priority,
            @RequestParam(required = false) String tag,
            @RequestParam(required = false) String search,
            @RequestParam(required = false) Boolean archived,
            @RequestParam(name = "due_after", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant dueAfter,
            @RequestParam(name = "due_before", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant dueBefore,
            @RequestParam(name = "include_deleted", defaultValue = "false") boolean includeDeleted,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "created_at,desc") String sort) {
        return ApiResponse.ok("todos fetched", todoService.list(status, priority, tag, search, archived, dueAfter, dueBefore, includeDeleted, page, size, sort));
    }

    @GetMapping("/overdue")
    @Operation(summary = "List overdue todos")
    public ApiResponse<List<TodoResponse>> overdue(@RequestParam(defaultValue = "20") int limit) {
        return ApiResponse.ok("overdue todos fetched", todoService.overdue(limit));
    }

    @GetMapping("/today")
    @Operation(summary = "List todos due today UTC")
    public ApiResponse<List<TodoResponse>> dueToday(@RequestParam(defaultValue = "20") int limit) {
        return ApiResponse.ok("today todos fetched", todoService.dueToday(limit));
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get a todo by id")
    public ApiResponse<TodoResponse> get(@PathVariable String id) {
        return ApiResponse.ok("todo fetched", todoService.get(id));
    }

    @PutMapping("/{id}")
    @Operation(summary = "Update todo fields", description = "Updates title, description, priority, due_date, and tags. Use the status endpoint for status transitions.")
    public ApiResponse<TodoResponse> update(@PathVariable String id, @Valid @RequestBody TodoUpdateRequest request) {
        return ApiResponse.ok("todo updated", todoService.update(id, request));
    }

    @PatchMapping("/{id}/status")
    @Operation(summary = "Change todo status")
    public ApiResponse<StatusChangeData> changeStatus(@PathVariable String id, @Valid @RequestBody TodoStatusChangeRequest request) {
        return ApiResponse.ok("todo status changed", todoService.changeStatus(id, request.status(), request.reason()));
    }

    @PostMapping("/{id}/complete")
    @Operation(summary = "Complete a todo")
    public ApiResponse<TodoResponse> complete(@PathVariable String id) {
        return ApiResponse.ok("todo completed", todoService.complete(id));
    }

    @PostMapping("/{id}/archive")
    @Operation(summary = "Archive a todo")
    public ApiResponse<TodoResponse> archive(@PathVariable String id) {
        return ApiResponse.ok("todo archived", todoService.archive(id));
    }

    @PostMapping("/{id}/restore")
    @Operation(summary = "Restore an archived or soft-deleted todo")
    public ApiResponse<TodoResponse> restore(@PathVariable String id) {
        return ApiResponse.ok("todo restored", todoService.restore(id));
    }

    @GetMapping("/{id}/history")
    @Operation(summary = "Get todo history")
    public ApiResponse<TodoHistoryData> history(@PathVariable String id) {
        return ApiResponse.ok("todo history fetched", todoService.history(id));
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "Soft delete a todo")
    public ApiResponse<DeleteTodoData> softDelete(@PathVariable String id) {
        return ApiResponse.ok("todo soft deleted", todoService.softDelete(id));
    }

    @DeleteMapping("/{id}/hard")
    @Operation(summary = "Hard delete a todo", description = "Allowed only for role=service, role=system, or role=admin with admin_status=approved.")
    public ApiResponse<DeleteTodoData> hardDelete(@PathVariable String id) {
        return ApiResponse.ok("todo hard deleted", todoService.hardDelete(id));
    }
}
