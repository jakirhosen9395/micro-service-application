package com.microservice.todo.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {
    @Bean
    public OpenAPI todoOpenApi(TodoProperties properties) {
        final String bearer = "bearerAuth";
        return new OpenAPI()
                .info(new Info()
                        .title("Todo List Service API")
                        .version(properties.getServiceVersion())
                        .description("Todo CRUD, status, archive, restore, delete, history, health APIs."))
                .components(new Components().addSecuritySchemes(bearer, new SecurityScheme()
                        .name(bearer)
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")))
                .addSecurityItem(new SecurityRequirement().addList(bearer));
    }
}
