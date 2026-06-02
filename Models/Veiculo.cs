using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EsteticaPorDoSol.Models
{
    public class Veiculo
    {
        [Key]
        public int idVeiculo { get; set; }
        public required string dsPlaca { get; set; }
        public required string dsModelo { get; set; }
        public required string dsCor { get; set; }
        [ForeignKey("Cliente")]
        public int idCliente { get; set; }
        public Cliente ?Cliente { get; set; }
    }
}
