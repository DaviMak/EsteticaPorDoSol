using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Carro
    {
        [Key]
        public int idCarro { get; set; }
        public required string dsPlaca { get; set; }
        public required string dsModelo { get; set; }
        public required string dsCor { get; set; }
        public int idCliente { get; set; }
        public required Cliente Cliente { get; set; }
    }
}
