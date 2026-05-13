package com.microservice.todo;

import com.microservice.todo.config.ElasticApmBootstrap;
import com.microservice.todo.config.RequiredEnvValidator;
import com.microservice.todo.config.TodoProperties;
import com.microservice.todo.env.EnvFileLoader;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.kafka.annotation.EnableKafka;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@EnableKafka
@SpringBootApplication
@EnableConfigurationProperties(TodoProperties.class)
public class TodoListServiceApplication {
    public static void main(String[] args) {
        EnvFileLoader.load(args);
        RequiredEnvValidator.validate();
        ElasticApmBootstrap.attachFromEnvironment();
        SpringApplication.run(TodoListServiceApplication.class, args);
    }
}
