using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    // Defina seus DbSets aqui, por exemplo:
    // public DbSet<Produto> Produtos { get; set; }

    public DbSet<Cliente> tbClientes { get; set; }
    public DbSet<Servico> tbServicos { get; set; }
    public DbSet<Atendimento> tbAtendimentos { get; set; }
    public DbSet<AtendimentoServico> tbAtendimentoServicos { get; set; }
   
}