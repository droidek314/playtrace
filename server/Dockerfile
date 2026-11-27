# Playtrace server image. Build from the server/ directory: docker build -t playtrace-server .
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY global.json Directory.Build.props ./
COPY src/Playtrace.Server/Playtrace.Server.csproj src/Playtrace.Server/
RUN dotnet restore src/Playtrace.Server/Playtrace.Server.csproj
COPY src/ src/
RUN dotnet publish src/Playtrace.Server/Playtrace.Server.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app
ENTRYPOINT ["dotnet", "Playtrace.Server.dll"]
