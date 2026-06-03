using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace EsteticaPorDoSol.Controllers
{
    public class AtendimentoController : Controller
    {
        private readonly ApplicationDbContext _context;

        public AtendimentoController(ApplicationDbContext context)
        {
            _context = context;
        }

        // Busca veículo pela placa para iniciar atendimento
        [HttpGet]
        public IActionResult BuscarVeiculo()
        {
            ViewBag.Placas = _context.tbVeiculos.Select(v => v.dsPlaca).ToList();
            return View();
        }

        [HttpPost]
        public IActionResult BuscarVeiculo(string busca)
        {
            var veiculo = _context.tbVeiculos
                .Include(v => v.Cliente)
                .FirstOrDefault(v =>
                    v.dsPlaca.ToUpper() == busca.ToUpper() ||
                    v.Cliente.dsNome.ToUpper().Contains(busca.ToUpper()));

            if (veiculo == null)
            {
                TempData["Mensagem"] = "Veículo não encontrado.";
                return RedirectToAction("Entrada", "Home");
            }

            return RedirectToAction("NovoAtendimento", new { idVeiculo = veiculo.idVeiculo });
        }

        // Abre tela de novo atendimento com o veículo já selecionado
        [HttpGet]
        public IActionResult NovoAtendimento(int idVeiculo)
        {
            var veiculo = _context.tbVeiculos
                .Include(v => v.Cliente)
                .FirstOrDefault(v => v.idVeiculo == idVeiculo);

            if (veiculo == null)
            {
                TempData["Mensagem"] = "Veículo não encontrado.";
                return RedirectToAction("TelaInicial", "Home");
            }

            ViewBag.Veiculo = veiculo;
            ViewBag.Servicos = _context.tbServicos.ToList();
            return View();
        }

        // Salva o atendimento
        [HttpPost]
        public IActionResult NovoAtendimento(int idVeiculo, List<int> servicosSelecionados, List<decimal> valoresServicos)
        {
            var veiculo = _context.tbVeiculos
                .Include(v => v.Cliente)
                .FirstOrDefault(v => v.idVeiculo == idVeiculo);

            if (veiculo == null || servicosSelecionados == null || !servicosSelecionados.Any())
            {
                TempData["Mensagem"] = "Selecione ao menos um serviço.";
                return RedirectToAction("NovoAtendimento", new { idVeiculo });
            }

            var atendimento = new Atendimento
            {
                idCliente = veiculo.idCliente,
                idVeiculo = veiculo.idVeiculo,
                dtDataHoraAtendimento = DateTime.Now,
                dsStatus = "Aberto"
            };

            _context.tbAtendimentos.Add(atendimento);
            _context.SaveChanges();

            decimal total = 0;
            for (int i = 0; i < servicosSelecionados.Count; i++)
            {
                var idServico = servicosSelecionados[i];
                var valorEditado = valoresServicos != null && i < valoresServicos.Count
                    ? valoresServicos[i]
                    : (_context.tbServicos.Find(idServico)?.vlServico ?? 0);

                _context.tbAtendimentoServicos.Add(new AtendimentoServico
                {
                    idAtendimento = atendimento.idAtendimento,
                    idServico = idServico,
                    vlServicoNoMomento = valorEditado
                });
                total += valorEditado;
            }

            atendimento.vlTotal = total;
            _context.SaveChanges();

            TempData["Mensagem"] = "Atendimento registrado com sucesso!";
            return RedirectToAction("TelaInicial", "Home");
        }

        // Lista atendimentos em aberto (para tela de Saída)
        [HttpGet]
        public IActionResult Saida()
        {
            var atendimentos = _context.tbAtendimentos
                .Include(a => a.Veiculo)
                .Include(a => a.Cliente)
                .Include(a => a.AtendimentoServicos)
                    .ThenInclude(s => s.Servico)
                .Where(a => a.dsStatus == "Aberto")
                .ToList();

            return View(atendimentos);
        }

        // Finaliza o atendimento
        [HttpPost]
        public IActionResult FinalizarAtendimento(int idAtendimento)
        {
            var atendimento = _context.tbAtendimentos.Find(idAtendimento);
            if (atendimento != null)
            {
                atendimento.dsStatus = "Finalizado";
                atendimento.dtDataHoraSaida = DateTime.Now;
                _context.SaveChanges();
                TempData["Mensagem"] = "Atendimento finalizado com sucesso!";
            }
            return RedirectToAction("Saida");
        }

        // Histórico por placa
        [HttpGet]
        public IActionResult BuscarPorPlaca(string placa)
        {
            ViewBag.Placas = _context.tbVeiculos.Select(v => v.dsPlaca).ToList();
            ViewBag.Nomes = _context.tbClientes.Select(c => c.dsNome).ToList();

            if (string.IsNullOrEmpty(placa))
                return View(null);

            var veiculo = _context.tbVeiculos
                .Include(v => v.Cliente)
                .FirstOrDefault(v =>
                    v.dsPlaca.ToUpper() == placa.ToUpper() ||
                    v.Cliente.dsNome.ToUpper().Contains(placa.ToUpper()));

            if (veiculo == null)
            {
                TempData["Erro"] = "Veículo não encontrado.";
                return View(null);
            }

            var historico = _context.tbAtendimentos
                .Include(a => a.AtendimentoServicos)
                    .ThenInclude(s => s.Servico)
                .Where(a => a.idVeiculo == veiculo.idVeiculo)
                .OrderByDescending(a => a.dtDataHoraAtendimento)
                .ToList();

            ViewBag.Veiculo = veiculo;
            return View(historico);
        }

        [HttpGet]
        public IActionResult Historico()
        {
            var atendimentos = _context.tbAtendimentos
                .Include(a => a.Veiculo)
                .Include(a => a.Cliente)
                .Include(a => a.AtendimentoServicos)
                    .ThenInclude(s => s.Servico)
                .OrderByDescending(a => a.dtDataHoraAtendimento)
                .ToList();

            return View(atendimentos);
        }
    }
}