using System.Threading.RateLimiting;
using biometricsAPI.Data;
using biometricsAPI.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;

// dotnet run -- genkey <BranchGUID> "<Branch name>"   -> creates a new branch API key
if (args.Length > 0 && args[0] == "genkey")
    return ApiKeyHasher.RunGenKeyCommand(args);

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Central")));
builder.Services.AddScoped<EmployeeRepository>();

builder.Services.AddAuthentication(ApiKeyAuthenticationHandler.SchemeName)
    .AddScheme<AuthenticationSchemeOptions, ApiKeyAuthenticationHandler>(ApiKeyAuthenticationHandler.SchemeName, null);
builder.Services.AddAuthorization();

// Slows down key guessing: max 120 requests per minute per client IP.
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 120, Window = TimeSpan.FromMinutes(1) }));
});

// Clients may send "Content-Encoding: gzip" bodies (JSON shrinks ~10x).
builder.Services.AddRequestDecompression();

builder.Services.AddControllers();
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.AddSecurityDefinition("BranchId", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.ApiKey,
        In = ParameterLocation.Header,
        Name = ApiKeyAuthenticationHandler.BranchHeader,
        Description = "Branch GUID",
    });
    c.AddSecurityDefinition("ApiKey", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.ApiKey,
        In = ParameterLocation.Header,
        Name = ApiKeyAuthenticationHandler.KeyHeader,
        Description = "Branch API key",
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        [new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "BranchId" } }] = Array.Empty<string>(),
        [new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "ApiKey" } }] = Array.Empty<string>(),
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRateLimiter();
app.UseRequestDecompression();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
return 0;
