using System.Text.Json;
using Basket.API.Services.Interfaces;
using Models;

namespace Basket.API.Services
{
    public class CatalogService : ICatalogService
    {
        private HttpClient _httpClient;
        private JsonSerializerOptions _options;

        private readonly string _baseUrl;

        public CatalogService(HttpClient httpClient, IConfiguration configuration)
        {
            _httpClient = httpClient;
            _baseUrl = (configuration.GetValue<string>("Catalog:BaseUrl") ?? "http://localhost:6001").TrimEnd('/');

            _options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
        }

        public async Task<Concert> GetConcert(string concertId)
        {
            return JsonSerializer.Deserialize<Concert>(await _httpClient.GetStringAsync($"{_baseUrl}/api/v1/catalog/items/{concertId}"), _options);
        }
    }
}