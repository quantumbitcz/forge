# Diagram Patterns

Mermaid and PlantUML patterns for common diagram types. Mermaid is the default — it renders natively in GitHub and GitLab without additional tooling.

## C4 Context Diagram

Shows the system and its relationships with external actors and systems.

```mermaid
C4Context
    title System Context — {system_name}
    Person(user, "User", "End user of the system")
    Person_Ext(admin, "Administrator", "Manages configuration")

    System(system, "{system_name}", "Core application")
    System_Ext(auth, "Identity Provider", "Authentication and authorization")
    System_Ext(email, "Email Service", "Transactional email delivery")

    Rel(user, system, "Uses", "HTTPS")
    Rel(admin, system, "Manages", "HTTPS")
    Rel(system, auth, "Delegates auth to", "OIDC")
    Rel(system, email, "Sends emails via", "SMTP/API")
```

## C4 Component Diagram

Shows the internal structure of a container (application or service).

```mermaid
C4Component
    title Components — {service_name}
    Container_Boundary(api, "API Service") {
        Component(controller, "Controller", "Spring MVC / Express", "Handles HTTP requests")
        Component(usecase, "Use Case", "Domain logic", "Orchestrates business operations")
        Component(repo, "Repository", "JPA / Prisma", "Persists and retrieves data")
    }

    ContainerDb(db, "Database", "PostgreSQL", "Stores application data")
    Container_Ext(cache, "Cache", "Redis", "Session and query cache")

    Rel(controller, usecase, "Calls")
    Rel(usecase, repo, "Calls")
    Rel(repo, db, "Reads/writes", "SQL")
    Rel(usecase, cache, "Reads/writes", "Redis protocol")
```

## Sequence Diagram

Shows interactions between components over time.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant API as API Gateway
    participant Auth as Auth Service
    participant Service as Domain Service
    participant DB as Database

    User->>+API: POST /resource {payload}
    API->>+Auth: Validate token
    Auth-->>-API: Token valid, claims: {roles}
    API->>+Service: createResource(command)
    Service->>+DB: INSERT INTO resources
    DB-->>-Service: resource_id
    Service-->>-API: ResourceCreated {id}
    API-->>-User: 201 Created {id}
```

## ER Diagram

Shows data entities and their relationships.

```mermaid
erDiagram
    USER {
        uuid id PK
        string email UK
        string name
        timestamp created_at
    }
    ORGANIZATION {
        uuid id PK
        string name
        timestamp created_at
    }
    MEMBERSHIP {
        uuid user_id FK
        uuid organization_id FK
        string role
        timestamp joined_at
    }
    RESOURCE {
        uuid id PK
        uuid organization_id FK
        string title
        string status
        timestamp created_at
    }

    USER ||--o{ MEMBERSHIP : "belongs to"
    ORGANIZATION ||--o{ MEMBERSHIP : "has"
    ORGANIZATION ||--o{ RESOURCE : "owns"
```

## Class Diagram

Shows class structures and relationships in the domain model.

```mermaid
classDiagram
    class User {
        +UserId id
        +Email email
        +UserName name
        +create(email, name) User$
        +changeName(name) User
    }
    class UserId {
        +UUID value
    }
    class Email {
        +String value
        +validate() Boolean
    }
    class UserRepository {
        <<interface>>
        +findById(id) User
        +save(user) User
        +delete(id) void
    }
    class UserRepositoryImpl {
        -DataSource ds
        +findById(id) User
        +save(user) User
        +delete(id) void
    }

    User *-- UserId : has
    User *-- Email : has
    UserRepositoryImpl ..|> UserRepository : implements
    UserRepositoryImpl ..> User : manages
```

## State Diagram

Shows state transitions for an entity or process.

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Submitted : submit()
    Submitted --> UnderReview : assign(reviewer)
    UnderReview --> Approved : approve()
    UnderReview --> Rejected : reject(reason)
    Rejected --> Draft : revise()
    Approved --> Published : publish()
    Published --> Archived : archive()
    Archived --> [*]
```

## PlantUML Alternative

Use PlantUML when Mermaid cannot express the required diagram type (e.g., deployment diagrams, advanced sequence features). Requires PlantUML server or local render step.

```plantuml
@startuml
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Context.puml

Person(user, "User", "End user")
System(system, "{system_name}", "Core application")
Rel(user, system, "Uses", "HTTPS")

@enduml
```

## Dos and Don'ts

**Dos:**
- Use Mermaid for GitHub/GitLab — no render step required
- Keep diagrams focused — one concept per diagram
- Use `autonumber` in sequence diagrams with 5+ steps
- Title every C4 diagram (`title ...`)

**Don'ts:**
- Don't put more than 10 nodes in a single diagram — split it
- Don't use PlantUML for diagrams Mermaid handles equally well
- Don't embed diagrams in code comments — reference the doc file instead
