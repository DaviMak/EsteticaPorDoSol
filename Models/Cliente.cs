using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Cliente
    {
        [Key]
        public int idCliente { get; set; }
        public required string dsNome { get; set; }
        public required string nrTelefone { get; set; }
        public required string dsPlaca { get; set; }
        public required string dsModelo { get; set; }
    }
}
