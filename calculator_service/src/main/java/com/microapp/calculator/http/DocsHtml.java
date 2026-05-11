package com.microapp.calculator.http;

import com.microapp.calculator.config.AppProperties;

public final class DocsHtml {

    private DocsHtml() {
    }

    public static String html(AppProperties props) {
        return """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8" />
                  <meta name="viewport" content="width=device-width, initial-scale=1" />
                  <title>Calculator Service API</title>
                  <link rel="icon" href="data:," />
                  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.19.0/swagger-ui.css" />
                  <style>
                    html, body {
                      margin: 0;
                      padding: 0;
                      width: 100%;
                      min-height: 100%;
                      background: #ffffff;
                    }
                    #swagger-ui {
                      width: 100%;
                    }
                    .swagger-ui .topbar {
                      display: none;
                    }
                    .swagger-ui .wrapper {
                      max-width: 1460px;
                      padding: 0 20px;
                    }
                    .swagger-ui .scheme-container {
                      padding: 20px;
                      box-shadow: none;
                      border-bottom: 1px solid #e5e7eb;
                    }
                  </style>
                </head>
                <body>
                  <div id="swagger-ui"></div>
                  <script src="https://unpkg.com/swagger-ui-dist@5.19.0/swagger-ui-bundle.js"></script>
                  <script src="https://unpkg.com/swagger-ui-dist@5.19.0/swagger-ui-standalone-preset.js"></script>
                  <script>
                    const openApiSpec = __OPENAPI__;
                    openApiSpec.servers = [
                      {
                        url: window.location.origin,
                        description: "same-origin server"
                      }
                    ];

                    function safeRandomId(prefix) {
                      if (window.crypto && typeof window.crypto.randomUUID === 'function') {
                        return prefix + '-' + window.crypto.randomUUID();
                      }
                      return prefix + '-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 12);
                    }

                    function normalizeAuthorizationHeader(headers) {
                      const current = headers['Authorization'] || headers['authorization'];
                      if (!current) {
                        return;
                      }
                      let value = String(current).trim();
                      if (!value) {
                        return;
                      }
                      const lower = value.toLowerCase();
                      if (lower.startsWith('bearer bearer ')) {
                        value = 'Bearer ' + value.substring(14).trim();
                      } else if (!lower.startsWith('bearer ') && value.split('.').length === 3) {
                        value = 'Bearer ' + value;
                      }
                      headers['Authorization'] = value;
                      if (headers['authorization']) {
                        delete headers['authorization'];
                      }
                    }

                    window.ui = SwaggerUIBundle({
                      spec: openApiSpec,
                      dom_id: '#swagger-ui',
                      layout: 'StandaloneLayout',
                      deepLinking: true,
                      persistAuthorization: true,
                      displayRequestDuration: true,
                      tryItOutEnabled: true,
                      supportedSubmitMethods: ['get', 'post', 'put', 'patch', 'delete', 'options', 'head'],
                      filter: true,
                      docExpansion: 'list',
                      defaultModelsExpandDepth: -1,
                      defaultModelExpandDepth: -1,
                      validatorUrl: null,
                      syntaxHighlight: {
                        activated: false
                      },
                      presets: [
                        SwaggerUIBundle.presets.apis,
                        SwaggerUIStandalonePreset
                      ],
                      requestInterceptor: (req) => {
                        req.headers = req.headers || {};
                        normalizeAuthorizationHeader(req.headers);
                        if (!req.headers['X-Request-ID']) {
                          req.headers['X-Request-ID'] = safeRandomId('req');
                        }
                        if (!req.headers['X-Trace-ID']) {
                          req.headers['X-Trace-ID'] = safeRandomId('trace');
                        }
                        if (!req.headers['X-Correlation-ID']) {
                          req.headers['X-Correlation-ID'] = safeRandomId('corr');
                        }
                        return req;
                      },
                      responseInterceptor: (res) => res
                    });
                  </script>
                </body>
                </html>
                """
                .replace("__OPENAPI__", openApi(props));
    }

    private static String openApi(AppProperties props) {
        return """
                {
                  "openapi": "3.0.3",
                  "info": {
                    "title": "Calculator Service API",
                    "version": "__VERSION__",
                    "description": "Interactive API console for calculator_service. Login through auth_service, copy access_token, click Authorize, and paste only the token value. Swagger sends Authorization: Bearer <token>."
                  },
                  "tags": [
                    {
                      "name": "system",
                      "description": "Public system endpoints"
                    },
                    {
                      "name": "calculator",
                      "description": "JWT-protected calculator APIs"
                    }
                  ],
                  "components": {
                    "securitySchemes": {
                      "bearerAuth": {
                        "type": "http",
                        "scheme": "bearer",
                        "bearerFormat": "JWT",
                        "description": "Paste only the access_token value from auth_service. Swagger sends Authorization: Bearer <token>."
                      }
                    },
                    "schemas": {
                      "CalculateRequestOperation": {
                        "type": "object",
                        "required": ["operation", "operands"],
                        "properties": {
                          "operation": {
                            "type": "string",
                            "enum": [
                              "ADD",
                              "SUBTRACT",
                              "MULTIPLY",
                              "DIVIDE",
                              "MODULO",
                              "POWER",
                              "SQRT",
                              "PERCENTAGE",
                              "SIN",
                              "COS",
                              "TAN",
                              "LOG",
                              "LN",
                              "ABS",
                              "ROUND",
                              "FLOOR",
                              "CEIL",
                              "FACTORIAL"
                            ],
                            "example": "ADD"
                          },
                          "operands": {
                            "type": "array",
                            "items": {
                              "type": "number",
                              "format": "double"
                            },
                            "example": [10, 20]
                          }
                        }
                      },
                      "CalculateRequestExpression": {
                        "type": "object",
                        "required": ["expression"],
                        "properties": {
                          "expression": {
                            "type": "string",
                            "example": "sqrt(16)+(10+5)*3"
                          }
                        }
                      }
                    }
                  },
                  "paths": {
                    "/hello": {
                      "get": {
                        "tags": ["system"],
                        "security": [],
                        "summary": "Service identity check",
                        "responses": {
                          "200": {
                            "description": "Service is running"
                          }
                        }
                      }
                    },
                    "/health": {
                      "get": {
                        "tags": ["system"],
                        "security": [],
                        "summary": "Dependency health check",
                        "responses": {
                          "200": {
                            "description": "All dependencies healthy"
                          },
                          "503": {
                            "description": "One or more dependencies down"
                          }
                        }
                      }
                    },
                    "/docs": {
                      "get": {
                        "tags": ["system"],
                        "security": [],
                        "summary": "Interactive embedded API console",
                        "responses": {
                          "200": {
                            "description": "Swagger UI HTML"
                          }
                        }
                      }
                    },
                    "/v1/calculator/operations": {
                      "get": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "List supported operations",
                        "description": "No database write. May use in-memory operation descriptors only.",
                        "responses": {
                          "200": {
                            "description": "Operations loaded"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          }
                        }
                      }
                    },
                    "/v1/calculator/calculate": {
                      "post": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "Execute operation or expression calculation",
                        "description": "Exactly one mode is accepted. Success persists a calculation, inserts a transactional outbox event, writes an S3 audit snapshot, caches the record, invalidates history cache, logs to MongoDB, and creates APM spans.",
                        "requestBody": {
                          "required": true,
                          "content": {
                            "application/json": {
                              "schema": {
                                "oneOf": [
                                  {
                                    "$ref": "#/components/schemas/CalculateRequestOperation"
                                  },
                                  {
                                    "$ref": "#/components/schemas/CalculateRequestExpression"
                                  }
                                ]
                              },
                              "examples": {
                                "operation": {
                                  "summary": "Operation mode",
                                  "value": {
                                    "operation": "ADD",
                                    "operands": [10, 20]
                                  }
                                },
                                "expression": {
                                  "summary": "Expression mode",
                                  "value": {
                                    "expression": "sqrt(16)+(10+5)*3"
                                  }
                                }
                              }
                            }
                          }
                        },
                        "responses": {
                          "200": {
                            "description": "Calculation completed"
                          },
                          "400": {
                            "description": "Invalid operation, operand count, divide by zero, too-long expression, or invalid expression"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          }
                        }
                      }
                    },
                    "/v1/calculator/history": {
                      "get": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "Get caller calculation history",
                        "description": "Reads Redis first, then PostgreSQL on cache miss, then stores a TTL cache entry.",
                        "parameters": [
                          {
                            "name": "limit",
                            "in": "query",
                            "required": false,
                            "schema": {
                              "type": "integer",
                              "minimum": 1,
                              "default": 50
                            },
                            "example": 50
                          }
                        ],
                        "responses": {
                          "200": {
                            "description": "History loaded"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          }
                        }
                      },
                      "delete": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "Soft-clear caller calculation history",
                        "description": "Sets deleted_at, inserts calculation.history.cleared into outbox, writes S3 audit, and invalidates Redis history cache.",
                        "responses": {
                          "200": {
                            "description": "History cleared"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          }
                        }
                      }
                    },
                    "/v1/calculator/history/{userId}": {
                      "get": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "Get another user's history when authorized",
                        "description": "Allowed for same user, approved admin, service/system role, or active local projected access grant with calculator scope. No synchronous Admin/User/Auth calls.",
                        "parameters": [
                          {
                            "name": "userId",
                            "in": "path",
                            "required": true,
                            "schema": {
                              "type": "string",
                              "minLength": 1
                            },
                            "example": "usr_123"
                          },
                          {
                            "name": "limit",
                            "in": "query",
                            "required": false,
                            "schema": {
                              "type": "integer",
                              "minimum": 1,
                              "default": 50
                            },
                            "example": 50
                          }
                        ],
                        "responses": {
                          "200": {
                            "description": "History loaded"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          }
                        }
                      }
                    },
                    "/v1/calculator/records/{calculationId}": {
                      "get": {
                        "tags": ["calculator"],
                        "security": [
                          {
                            "bearerAuth": []
                          }
                        ],
                        "summary": "Get one calculation record",
                        "description": "Reads Redis first, falls back to PostgreSQL, then applies the same read authorization rules as history.",
                        "parameters": [
                          {
                            "name": "calculationId",
                            "in": "path",
                            "required": true,
                            "schema": {
                              "type": "string",
                              "minLength": 1
                            },
                            "example": "calc_123"
                          }
                        ],
                        "responses": {
                          "200": {
                            "description": "Record loaded"
                          },
                          "401": {
                            "description": "Missing, invalid, or expired JWT"
                          },
                          "403": {
                            "description": "Tenant mismatch or insufficient read permission"
                          },
                          "404": {
                            "description": "Calculation record not found"
                          }
                        }
                      }
                    }
                  }
                }
                """.replace("__VERSION__", jsonEscape(props.getVersion()));
    }

    private static String jsonEscape(String value) {
        if (value == null) {
            return "";
        }

        return value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\b", "\\b")
                .replace("\f", "\\f")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
