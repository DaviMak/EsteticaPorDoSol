using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc;

namespace EsteticaPorDoSol.Controllers
{
    public class CarroController : Controller
    {
        private readonly ApplicationDbContext _context;

        public CarroController(ApplicationDbContext context)
        {
            _context = context;
        }

        public IActionResult ListarCarro()
        {
            var listaCarros = _context.tbCarros.ToList();
            return View(listaCarros);
        }

        public IActionResult Excluir(int id)
        {
            var carro = _context.tbCarros.Find(id);
            if (carro != null)
            {
                _context.tbCarros.Remove(carro);
                _context.SaveChanges();
                ViewBag.Mensagem = "Carro excluído com sucesso!";
            }
            else
            {
                ViewBag.Mensagem = "Carro não encontrado.";
            }
            return RedirectToAction("ListarCarro");
        }

        public IActionResult Editar(int id)
        {
            var carro = _context.tbCarros.Find(id);
            if (carro == null)
            {
                TempData["Mensagem"] = "Carro não encontrado.";
                return RedirectToAction("ListarCarro");
            }

            return View("EditarCarro", carro);
        }
        [HttpPost]
        public IActionResult EditarCarro(Carro carro)
        {
            try
            {
                _context.tbCarros.Update(carro);
                _context.SaveChanges();
                ViewBag.Mensagem = "Carro atualizado com sucesso!";
                return RedirectToAction("ListarCarro");
            }
            catch (Exception ex)
            {
                ViewBag.Mensagem = $"Erro ao atualizar carro: {ex.Message}";
                return View("EditarCarro", carro);
            }
        }
        [HttpGet]
        public IActionResult Cadastrar()
        {
            ViewBag.Clientes = _context.tbClientes.ToList();
            return View("CadastrarCarro");
        }

        [HttpPost]
        public IActionResult CadastrarCarro(Carro carro)
        {
            //carro.Cliente = _context.tbClientes.Find(carro.idCliente);
            if (ModelState.IsValid)
            {
                _context.tbCarros.Add(carro);
                _context.SaveChanges();
                ViewBag.Mensagem = "Veiculo cadastrado com sucesso!";
                return RedirectToAction("ListarCarro");
            }
            TempData["Mensagem"] = "Erro ao cadastrar Veiculo. Verifique os dados e tente novamente.";
            ViewBag.Clientes = _context.tbClientes.ToList();

            return View("CadastrarCarro", carro);
        }
    }
}
