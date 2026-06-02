using System;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EsteticaPorDoSol.Migrations
{
    /// <inheritdoc />
    public partial class CriacaoInicial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateTable(
                name: "tbClientes",
                columns: table => new
                {
                    idCliente = table.Column<int>(type: "int", nullable: false)
                        .Annotation("MySql:ValueGenerationStrategy", MySqlValueGenerationStrategy.IdentityColumn),
                    dsNome = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    nrTelefone = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tbClientes", x => x.idCliente);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateTable(
                name: "tbServicos",
                columns: table => new
                {
                    idServico = table.Column<int>(type: "int", nullable: false)
                        .Annotation("MySql:ValueGenerationStrategy", MySqlValueGenerationStrategy.IdentityColumn),
                    dsNomeServico = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    dsDescricaoServico = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    vlServico = table.Column<decimal>(type: "decimal(65,30)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tbServicos", x => x.idServico);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateTable(
                name: "tbAtendimentos",
                columns: table => new
                {
                    idAtendimento = table.Column<int>(type: "int", nullable: false)
                        .Annotation("MySql:ValueGenerationStrategy", MySqlValueGenerationStrategy.IdentityColumn),
                    idCliente = table.Column<int>(type: "int", nullable: false),
                    dtDataHoraAtendimento = table.Column<DateTime>(type: "datetime(6)", nullable: false),
                    ClienteidCliente = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tbAtendimentos", x => x.idAtendimento);
                    table.ForeignKey(
                        name: "FK_tbAtendimentos_tbClientes_ClienteidCliente",
                        column: x => x.ClienteidCliente,
                        principalTable: "tbClientes",
                        principalColumn: "idCliente",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateTable(
                name: "tbVeiculos",
                columns: table => new
                {
                    idVeiculo = table.Column<int>(type: "int", nullable: false)
                        .Annotation("MySql:ValueGenerationStrategy", MySqlValueGenerationStrategy.IdentityColumn),
                    dsPlaca = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    dsModelo = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    dsCor = table.Column<string>(type: "longtext", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    idCliente = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tbVeiculos", x => x.idVeiculo);
                    table.ForeignKey(
                        name: "FK_tbVeiculos_tbClientes_idCliente",
                        column: x => x.idCliente,
                        principalTable: "tbClientes",
                        principalColumn: "idCliente",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateTable(
                name: "tbAtendimentoServicos",
                columns: table => new
                {
                    idAtendimentoServico = table.Column<int>(type: "int", nullable: false)
                        .Annotation("MySql:ValueGenerationStrategy", MySqlValueGenerationStrategy.IdentityColumn),
                    idAtendimento = table.Column<int>(type: "int", nullable: false),
                    idServico = table.Column<int>(type: "int", nullable: false),
                    vlServicoNoMomento = table.Column<decimal>(type: "decimal(65,30)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tbAtendimentoServicos", x => x.idAtendimentoServico);
                    table.ForeignKey(
                        name: "FK_tbAtendimentoServicos_tbAtendimentos_idAtendimento",
                        column: x => x.idAtendimento,
                        principalTable: "tbAtendimentos",
                        principalColumn: "idAtendimento",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_tbAtendimentoServicos_tbServicos_idServico",
                        column: x => x.idServico,
                        principalTable: "tbServicos",
                        principalColumn: "idServico",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "IX_tbAtendimentos_ClienteidCliente",
                table: "tbAtendimentos",
                column: "ClienteidCliente");

            migrationBuilder.CreateIndex(
                name: "IX_tbAtendimentoServicos_idAtendimento",
                table: "tbAtendimentoServicos",
                column: "idAtendimento");

            migrationBuilder.CreateIndex(
                name: "IX_tbAtendimentoServicos_idServico",
                table: "tbAtendimentoServicos",
                column: "idServico");

            migrationBuilder.CreateIndex(
                name: "IX_tbVeiculos_idCliente",
                table: "tbVeiculos",
                column: "idCliente");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "tbAtendimentoServicos");

            migrationBuilder.DropTable(
                name: "tbVeiculos");

            migrationBuilder.DropTable(
                name: "tbAtendimentos");

            migrationBuilder.DropTable(
                name: "tbServicos");

            migrationBuilder.DropTable(
                name: "tbClientes");
        }
    }
}
