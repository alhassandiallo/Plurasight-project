using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Models;
using ServiceWorker.Services.Interfaces;
using System.Text.Json;

namespace ServiceWorker.Services
{
    public class CatalogService : ICatalogService
    {
        private HttpClient _httpClient;
        private JsonSerializerOptions _options;
        private ILogger<CatalogService> _logger;

        private readonly string _baseUrl;

        public CatalogService(HttpClient httpClient, ILogger<CatalogService> logger, IConfiguration configuration)
        {
            _httpClient = httpClient;
            _logger = logger;
            _baseUrl = (configuration.GetValue<string>("Catalog:BaseUrl") ?? "http://localhost:6001").TrimEnd('/');

            _options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
        }

        public async Task<Concert> GetConcert(string concertId)
        {
            _logger.LogInformation("Get Concert {concertId}", concertId);
            return JsonSerializer.Deserialize<Concert>(await _httpClient.GetStringAsync($"{_baseUrl}/api/v1/catalog/items/{concertId}"), _options);
        }
    }
}

