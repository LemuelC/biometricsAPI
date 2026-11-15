using System.Threading.RateLimiting;
using biometricsAPI.Data;
using biometricsAPI.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;

// dotnet run -- genkey <BranchGUID> "<Branch name>"   -> creates a new branch API key
if (args.Length > 0 && args[0] == "genkey")
    return ApiKeyHasher.RunGenKeyCommand(args);

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Central")));
builder.Services.AddScoped<UpsertRepository>();

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
    // One field in Swagger's Authorize dialog: "<BranchGUID>:<API key>".
    c.AddSecurityDefinition("ApiKey", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.ApiKey,
        In = ParameterLocation.Header,
        Name = ApiKeyAuthenticationHandler.KeyHeader,
        Description = "Enter BranchGUID:APIKey (colon between, no spaces), e.g. 531F69F9-CBC5-4210-B144-573E21A43874:AbC123...",
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        [new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "ApiKey" } }] = Array.Empty<string>(),
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.

// Unhandled errors -> JSON 500. The exception is always logged; its message is only put in the
// response when "ShowErrorDetails": true (turn on briefly to diagnose, e.g. database login errors).
app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var error = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var showDetails = app.Configuration.GetValue("ShowErrorDetails", false);
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await context.Response.WriteAsJsonAsync(new
    {
        status = 500,
        error = showDetails && error is not null
            ? $"{error.GetBaseException().GetType().Name}: {error.GetBaseException().Message}"
            : "Internal server error. Set \"ShowErrorDetails\": true in appsettings.json to see the reason.",
        traceId = context.TraceIdentifier,
    });
}));
// Swagger is on in every environment unless "EnableSwagger": false is set in appsettings.
// The docs are public, but every endpoint still requires a valid branch API key.
if (app.Configuration.GetValue("EnableSwagger", true))
{
    app.UseSwagger();
    // Relative path so the UI also works when hosted under an IIS sub-path (e.g. /biometricsapi/swagger).
    app.UseSwaggerUI(c => c.SwaggerEndpoint("v1/swagger.json", "biometricsAPI v1"));
}

if (!app.Environment.IsDevelopment())
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
