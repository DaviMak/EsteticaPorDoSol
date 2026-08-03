using Microsoft.AspNetCore.Mvc;

namespace EsteticaPorDoSol.Controllers
{
    public class LoginController : Controller
    {
        [HttpGet]
        public IActionResult TelaLogin()
        {
            return View();
        }

        [HttpPost]
        public IActionResult Entrar(string usuario, string senha)
        {
            if (usuario == "kelvin" && senha == "12345")
            {
                return RedirectToAction("TelaInicial", "Home");
            }

            TempData["Erro"] = "Usuário ou senha incorretos.";
            return RedirectToAction("TelaLogin");
        }
    }
}