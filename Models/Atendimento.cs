using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EsteticaPorDoSol.Models
{
    public class Atendimento
    {
        [Key]
        public int idAtendimento { get; set; }
        //[Required]
        public int idCliente { get; set; }
        public int idVeiculo { get; set; }
        public required DateTime dtDataHoraAtendimento { get; set; }
        public DateTime? dtDataHoraSaida { get; set; }
        public decimal vlTotal { get; set; }
        public string dsStatus { get; set; } = "Aberto";
        [ForeignKey("idCliente")]
        public Cliente Cliente { get; set; } = null!;

        [ForeignKey("idVeiculo")]
        public Veiculo Veiculo { get; set; } = null!;
        public List<AtendimentoServico> AtendimentoServicos { get; set; } = new();
    }
}
