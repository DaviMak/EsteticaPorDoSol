using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;

// O publish copia os estaticos para um wwwroot ao lado do binario; rodando via
// "dotnet run" eles continuam onde moram de verdade, na pasta front-end/.
var wwwrootPublicado = Path.Combine(AppContext.BaseDirectory, "wwwroot");
var webRoot = Directory.Exists(wwwrootPublicado)
    ? wwwrootPublicado
    : Path.Combine("..", "front-end", "wwwroot");

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    WebRootPath = webRoot
});

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseMySql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        ServerVersion.Parse("8.0-mysql")
    ));

// No Cloud Run o TLS termina no proxy e a requisicao chega no container como HTTP.
// Sem isso, UseHttpsRedirection entra em loop infinito de redirecionamento.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services.AddControllersWithViews();

var app = builder.Build();

app.UseForwardedHeaders();

// Aplica as migrations no startup: o deploy nao tem SDK para rodar "dotnet ef database update".
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    db.Database.Migrate();
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// No Cloud Run o proxy entrega HTTPS e o redirecionamento faz sentido. Atras do
// Nginx em VM, servindo apenas HTTP na porta 80, ele redirecionaria para uma
// porta 443 que ninguem escuta e derrubaria o site - por isso o interruptor.
if (app.Configuration.GetValue("UseHttpsRedirection", true))
{
    app.UseHttpsRedirection();
}

app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Login}/{action=TelaLogin}/{id?}");

app.Run();
