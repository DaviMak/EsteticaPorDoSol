using Microsoft.AspNetCore.Mvc;

namespace EsteticaPorDoSol.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
        public IActionResult TelaInicial()
        {
            return View();
        }
    }
}
