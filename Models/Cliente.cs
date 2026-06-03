using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Cliente
    {
        [Key]
        public int idCliente { get; set; }
        [Required(ErrorMessage = "Campo obrigatório")]
        public required string dsNome { get; set; }

        public string? nrTelefone { get; set; }
        public List<Veiculo> Veiculos { get; set; } = new();
    }
}
