using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Cliente> tbClientes { get; set; }
    public DbSet<Servico> tbServicos { get; set; }
    public DbSet<Atendimento> tbAtendimentos { get; set; }
    public DbSet<AtendimentoServico> tbAtendimentoServicos { get; set; }

}