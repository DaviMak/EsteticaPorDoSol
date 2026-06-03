using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EsteticaPorDoSol.Models
{
    public class Veiculo
    {
        [Key]
        public int idVeiculo { get; set; }
        [Required(ErrorMessage = "Campo obrigatório")]
        [StringLength(10, MinimumLength = 3, ErrorMessage = "A placa deve conter entre 3 e 10 caracteres.")]
        public required string dsPlaca { get; set; }
        [Required(ErrorMessage = "Campo obrigatório")]
        public required string dsModelo { get; set; }
        [Required(ErrorMessage = "Campo obrigatório")]
        public required string dsCor { get; set; }
        [ForeignKey("Cliente")]
        [Range(1, int.MaxValue, ErrorMessage = "Selecione um cliente")]
        public int idCliente { get; set; }
        
        public Cliente ?Cliente { get; set; }
    }
}
