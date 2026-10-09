FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish "ServiceWorker/ServiceWorker.csproj" -c Release -o /app/publish --no-self-contained

FROM mcr.microsoft.com/dotnet/runtime:7.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
USER 1654
ENTRYPOINT ["dotnet", "ServiceWorker.dll"]
