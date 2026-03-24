# ASP.NET + Elasticsearch (Elastic.Clients.Elasticsearch)

> Full-text search for ASP.NET using the official v8 Elastic.NET client with DI registration, typed search, and index management.

## Integration Setup

```bash
dotnet add package Elastic.Clients.Elasticsearch
```

## Framework-Specific Patterns

### DI registration in `Program.cs`
```csharp
// Program.cs
builder.Services.AddSingleton<ElasticsearchClient>(_ =>
{
    var settings = new ElasticsearchClientSettings(
        new Uri(builder.Configuration["Elasticsearch:Url"]!))
        .DefaultIndex("products")
        .Authentication(new BasicAuthentication(
            builder.Configuration["Elasticsearch:Username"]!,
            builder.Configuration["Elasticsearch:Password"]!));
    return new ElasticsearchClient(settings);
});
```

### Index management on startup
```csharp
// Infrastructure/ElasticsearchSetup.cs
public static class ElasticsearchSetup
{
    public static async Task EnsureIndicesAsync(ElasticsearchClient client)
    {
        var exists = await client.Indices.ExistsAsync("products");
        if (!exists.Exists)
        {
            await client.Indices.CreateAsync<ProductDocument>("products", c => c
                .Mappings(m => m
                    .Properties(p => p
                        .Text(t => t.Name, cfg => cfg.Analyzer("standard"))
                        .FloatNumber(f => f.Price))));
        }
    }
}

// Program.cs
var es = app.Services.GetRequiredService<ElasticsearchClient>();
await ElasticsearchSetup.EnsureIndicesAsync(es);
```

### Typed search service
```csharp
// Search/ProductSearchService.cs
public class ProductSearchService(ElasticsearchClient client)
{
    public async Task IndexAsync(ProductDocument doc) =>
        await client.IndexAsync(doc, "products");

    public async Task<IReadOnlyCollection<ProductDocument>> SearchAsync(string query)
    {
        var response = await client.SearchAsync<ProductDocument>(s => s
            .Index("products")
            .Query(q => q
                .MultiMatch(m => m
                    .Query(query)
                    .Fields(new[] { "name^3", "description" }))));

        response.ThrowIfNotSuccessfulResponse();
        return response.Documents;
    }

    public async Task DeleteAsync(string id) =>
        await client.DeleteAsync("products", id);
}
```

### Document model
```csharp
// Search/ProductDocument.cs
public record ProductDocument(
    [property: JsonPropertyName("id")]   string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("description")] string Description,
    [property: JsonPropertyName("price")] decimal Price
);
```

## Scaffolder Patterns
```
src/
  Infrastructure/
    ElasticsearchSetup.cs    # EnsureIndicesAsync called at startup
  Search/
    ProductDocument.cs       # record mapped to ES document
    ProductSearchService.cs  # typed search / index / delete
  Program.cs                 # DI + startup index check
appsettings.json             # Elasticsearch:Url/Username/Password
```

## Dos
- Register `ElasticsearchClient` as `Singleton` — it manages connection pooling internally
- Call `ThrowIfNotSuccessfulResponse()` or check `IsValidResponse` on every response
- Use typed document records with `[JsonPropertyName]` to control field names
- Create indices with explicit mappings at startup rather than relying on auto-mapping

## Don'ts
- Don't create a new `ElasticsearchClient` per request
- Don't inject the client directly into controllers — wrap in a service
- Don't use ES as the source of truth; sync from your primary DB
- Don't hardcode credentials in `appsettings.json` — use user secrets or environment variables
