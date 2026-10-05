# ETL de carga y validación de ventas con SSIS

Proyecto desarrollado con **SQL Server Integration Services (SSIS)** para implementar un proceso ETL de carga y validación de ventas recibidas mediante un archivo CSV.

El proceso extrae las ventas desde un archivo plano, realiza conversiones de tipos, calcula el importe total, aplica reglas de negocio, valida la existencia del cliente en SQL Server y separa los registros válidos de los rechazados. Las ventas válidas se almacenan en la tabla `dbo.Venta` y los registros que no cumplen las validaciones se escriben en un archivo CSV independiente con el motivo de rechazo.

---

## Objetivo del proyecto

Implementar un paquete SSIS que permita:

- Leer ventas desde un archivo CSV mediante **Origen de archivo plano / Flat File Source**.
- Convertir los datos recibidos a tipos compatibles con SQL Server.
- Calcular `ImporteTotal = Cantidad × PrecioUnitario` mediante **Columna derivada / Derived Column**.
- Validar que:
  - `Cantidad > 0`.
  - `PrecioUnitario > 0`.
  - `Estado = APROBADA`.
- Validar mediante **Lookup** que el `IdCliente` exista en `dbo.Cliente`.
- Insertar únicamente las ventas válidas en `dbo.Venta` mediante **Destino OLE DB**.
- Redirigir los registros inválidos o con errores de conversión a `Ventas_Rechazadas.csv`.
- Utilizar un **Flujo de control** con restricciones de precedencia para organizar la ejecución.

---

## Arquitectura general

```text
Ventas_Diarias.csv
        |
        v
SRC_CSV_Ventas
Origen de archivo plano
        |
        v
CNV_TiposDatos
Conversión de datos
       / \
      /   \ Error de conversión
     v     v
DRV_CalcularImporteTotal     DRV_RechazoConversion
        |                              |
        v                              |
CS_ValidarVenta                      |
   /          \                       |
  /            \                      |
 v              v                     |
VentaValida   VentaNoValida           |
  |              |                     |
  v              v                     |
LKP_ValidarCliente   DRV_RechazoReglas|
   /      \             |              |
  /        \            |              |
 v          v           |              |
Match      No Match     |              |
 |            |         |              |
 v            v         |              |
DRV_EstadoSQL  DRV_RechazoCliente     |
 |                |                    |
 v                |                    |
DST_SQL_Venta     +---------+----------+
                           |
                           v
                    UNN_Rechazados
                           |
                           v
                    DST_CSV_Rechazados
```

---

## Flujo de control

El paquete principal es:

```text
PKG_CargaVentas.dtsx
```

Su flujo de control contiene:

```text
EST_ValidarBaseDatos
        |
        | Correcto / Success
        v
DFT_ProcesarVentas
```

### `EST_ValidarBaseDatos`

Tarea **Ejecutar SQL** que comprueba que:

- La conexión apunte a `ETLVentasDB`.
- Exista `dbo.Cliente`.
- Exista `dbo.Venta`.
- La tabla `dbo.Cliente` contenga registros para realizar el Lookup.

### `DFT_ProcesarVentas`

Tarea **Flujo de datos** donde se ejecutan la extracción, transformación, validación, Lookup, carga y generación de rechazados.

---

## Componentes principales del Data Flow

### `SRC_CSV_Ventas`

Lee el archivo de entrada mediante **Origen de archivo plano**.

Columnas esperadas:

```text
IdVenta
FechaVenta
IdCliente
Producto
Cantidad
PrecioUnitario
Estado
```

Los datos se leen inicialmente como texto para permitir que los errores de formato sean capturados posteriormente por `CNV_TiposDatos`.

### `CNV_TiposDatos`

Realiza conversiones explícitas:

```text
IdVenta          -> DT_I4
FechaVenta       -> DT_DBDATE
IdCliente        -> DT_I4
Producto         -> DT_WSTR(150)
Cantidad         -> DT_I4
PrecioUnitario   -> DT_NUMERIC(18,2)
```

Los errores o truncamientos se configuran como **Redirigir fila**.

### `DRV_CalcularImporteTotal`

Crea la columna:

```text
ImporteTotal = Cantidad_Cnv * PrecioUnitario_Cnv
```

El resultado se mantiene como `DT_NUMERIC(18,2)`.

### `CS_ValidarVenta`

Separa las ventas según las reglas de negocio:

```text
Cantidad_Cnv > 0
AND PrecioUnitario_Cnv > 0
AND Estado = "APROBADA"
```

Salidas:

```text
VentaValida
VentaNoValida
```

### `LKP_ValidarCliente`

Consulta `dbo.Cliente` utilizando:

```text
IdCliente_Cnv -> dbo.Cliente.IdCliente
```

Salidas:

```text
Match    -> cliente existente
No Match -> cliente inexistente
```

### `DRV_EstadoSQL`

Convierte el estado de las ventas válidas a una cadena compatible con el destino SQL cuando la columna `dbo.Venta.Estado` utiliza `VARCHAR(20)`.

Expresión utilizada:

```text
(DT_STR,20,1252)Estado
```

Salida:

```text
Estado_SQL
```

### `DST_SQL_Venta`

Inserta las ventas válidas en:

```text
dbo.Venta
```

Mapeo principal:

```text
IdVenta_Cnv          -> IdVenta
FechaVenta_Cnv       -> FechaVenta
IdCliente_Cnv        -> IdCliente
Producto_Cnv         -> Producto
Cantidad_Cnv         -> Cantidad
PrecioUnitario_Cnv   -> PrecioUnitario
ImporteTotal         -> ImporteTotal
Estado_SQL           -> Estado
```

`FechaCarga` no se asigna desde SSIS porque SQL Server la genera mediante `DEFAULT (SYSDATETIME())`.

---

## Manejo de registros rechazados

El proceso genera tres tipos principales de rechazo.

### Errores de conversión

Componente:

```text
DRV_RechazoConversion
```

Motivo:

```text
ERROR_CONVERSION_DATOS
```

### Reglas de negocio

Componente:

```text
DRV_RechazoReglas
```

Posibles motivos:

```text
CANTIDAD_INVALIDA
PRECIO_INVALIDO
ESTADO_NO_APROBADO
```

### Cliente inexistente

Componente:

```text
DRV_RechazoCliente
```

Motivo:

```text
CLIENTE_NO_EXISTE
```

Las tres rutas se consolidan mediante:

```text
UNN_Rechazados
```

Finalmente se escriben mediante:

```text
DST_CSV_Rechazados
```

al archivo:

```text
Ventas_Rechazadas.csv
```

---

## Resultado esperado de la prueba incluida

El archivo de entrada contiene 14 registros diseñados para probar todos los caminos del ETL.

Distribución esperada:

```text
14 registros de entrada
|
+-- 11 conversiones correctas
|   |
|   +-- 5 cumplen las reglas de negocio
|   |   |
|   |   +-- 4 clientes existentes -> dbo.Venta
|   |   +-- 1 cliente inexistente -> rechazado
|   |
|   +-- 6 no cumplen las reglas -> rechazados
|
+-- 3 errores de conversión -> rechazados
```

Resultado final:

```text
4 ventas cargadas en dbo.Venta
10 registros almacenados en Ventas_Rechazadas.csv
```

Control de integridad del proceso:

```text
14 = 4 + 10
```

---

## Estructura del repositorio

```text
ETL_Ventas/
|
+-- Entrada/
|   +-- Ventas_Diarias.csv
|
+-- SQL/
|   +-- 01_CrearBaseDatos.sql
|
+-- Rechazados/
|   +-- Ventas_Rechazadas.csv
|
+-- Procesados/
|
+-- ProyectoSSIS/
|   +-- ETL_Ventas/
|       +-- ETL_Ventas.sln
|       +-- ETL_Ventas_SSIS/
|           +-- ETL_Ventas_SSIS.dtproj
|           +-- Project.params
|           +-- PKG_CargaVentas.dtsx
|
+-- Evidencias/
|
+-- .gitignore
+-- README.md
```

---

## Archivos importantes

### `SQL/01_CrearBaseDatos.sql`

Crea:

```text
ETLVentasDB
dbo.Cliente
dbo.Venta
```

Además crea las claves, relación entre Cliente y Venta, índice y clientes de prueba requeridos para el Lookup.

### `Entrada/Ventas_Diarias.csv`

Archivo de entrada del ETL. Debe existir antes de ejecutar el paquete.

### `Rechazados/Ventas_Rechazadas.csv`

Archivo generado por SSIS con los registros que no cumplen las validaciones.

### `ProyectoSSIS/ETL_Ventas/ETL_Ventas.sln`

Solución que debe abrirse en Visual Studio con la extensión de SQL Server Integration Services instalada.

### `Project.params`

Contiene parámetros de rutas reutilizables para evitar distribuir rutas físicas directamente por los componentes.

---

## Requisitos previos

Se requiere disponer de:

- SQL Server.
- SQL Server Management Studio (SSMS).
- Visual Studio con soporte para SQL Server Data Tools.
- Extensión **SQL Server Integration Services Projects 2022+**.
- Permisos de lectura y escritura sobre las carpetas utilizadas por el ETL.

---

## Configuración antes de ejecutar

### 1. Crear la base de datos

Abrir en SSMS:

```text
SQL/01_CrearBaseDatos.sql
```

y ejecutarlo.

Antes de continuar deben existir:

```text
ETLVentasDB
dbo.Cliente
dbo.Venta
```

La tabla `dbo.Cliente` debe contener los clientes de prueba incluidos en el script.

### 2. Configurar la conexión SQL

En Visual Studio revisar:

```text
CM_SQL_ETLVentas
```

La conexión debe apuntar a la instancia local de SQL Server donde fue creada `ETLVentasDB`.

Se recomienda utilizar **Autenticación de Windows** para evitar almacenar usuario y contraseña dentro del proyecto.

### 3. Ajustar las rutas del proyecto

En:

```text
Project.params
```

revisar los siguientes parámetros:

```text
pRutaEntrada
pRutaRechazados
pRutaProcesados
```

Ejemplo utilizado durante el desarrollo:

```text
pRutaEntrada    = D:\ETL_Ventas\Entrada\Ventas_Diarias.csv
pRutaRechazados = D:\ETL_Ventas\Rechazados\Ventas_Rechazadas.csv
pRutaProcesados = D:\ETL_Ventas\Procesados
```

Si el repositorio se encuentra en otra unidad o carpeta, estos valores deben actualizarse antes de ejecutar.

### 4. Archivo de entrada

Debe existir el archivo:

```text
Entrada/Ventas_Diarias.csv
```

El archivo utiliza:

```text
Delimitador: coma (,)
Codificación: UTF-8 / Code Page 65001
```

Para el Data Flow se utiliza configuración regional:

```text
English (United States) / LocaleID 1033
```

Esto permite interpretar correctamente valores con punto decimal, por ejemplo:

```text
150.50
899.90
35.75
```

### 5. Estado hacia SQL Server

El archivo de entrada trabaja en UTF-8, mientras que `dbo.Venta.Estado` utiliza `VARCHAR(20)`.

Por esta razón el paquete contiene `DRV_EstadoSQL`, que genera:

```text
Estado_SQL = (DT_STR,20,1252)Estado
```

Esta columna debe ser la utilizada en el mapeo de `DST_SQL_Venta`.

---

## Cómo ejecutar el proyecto

1. Ejecutar `SQL/01_CrearBaseDatos.sql` desde SSMS.
2. Verificar que `Entrada/Ventas_Diarias.csv` exista.
3. Abrir:

```text
ProyectoSSIS/ETL_Ventas/ETL_Ventas.sln
```

4. Revisar `CM_SQL_ETLVentas`.
5. Revisar `Project.params` y corregir rutas si fuese necesario.
6. Abrir:

```text
PKG_CargaVentas.dtsx
```

7. Ejecutar el paquete con **F5**.
8. Confirmar que `EST_ValidarBaseDatos` y `DFT_ProcesarVentas` finalicen correctamente.
9. Revisar `dbo.Venta` en SQL Server.
10. Revisar `Rechazados/Ventas_Rechazadas.csv`.

---

## Consultas de validación

### Ventas cargadas

```sql
USE ETLVentasDB;
GO

SELECT
    IdVenta,
    FechaVenta,
    IdCliente,
    Producto,
    Cantidad,
    PrecioUnitario,
    ImporteTotal,
    Estado,
    FechaCarga
FROM dbo.Venta
ORDER BY IdVenta;
```

### Comprobar reglas de negocio

```sql
SELECT *
FROM dbo.Venta
WHERE Cantidad <= 0
   OR PrecioUnitario <= 0
   OR Estado <> 'APROBADA';
```

El resultado esperado es **0 filas**.

### Comprobar clientes

```sql
SELECT
    V.IdVenta,
    V.IdCliente
FROM dbo.Venta AS V
LEFT JOIN dbo.Cliente AS C
    ON C.IdCliente = V.IdCliente
WHERE C.IdCliente IS NULL;
```

El resultado esperado es **0 filas**.

---

## Repetir una prueba con el mismo CSV

`IdVenta` es clave primaria de `dbo.Venta`. Si se intenta ejecutar varias veces el mismo archivo sin limpiar previamente los datos, SQL Server puede generar un error de clave duplicada.

Para repetir una prueba de desarrollo con el mismo archivo se puede ejecutar manualmente:

```sql
USE ETLVentasDB;
GO

TRUNCATE TABLE dbo.Venta;
```

Este `TRUNCATE` se utiliza únicamente para repetir pruebas y **no forma parte del paquete SSIS**.

En un escenario productivo se podría implementar un proceso incremental, staging o una validación adicional por `IdVenta`.

---

## Evidencias

Las capturas y evidencias de ejecución del proyecto se encuentran en:

```text
./Evidencias/
```

---

## Buenas prácticas aplicadas

- Nombres descriptivos para Tasks, transformaciones y destinos.
- Administradores de conexiones reutilizables.
- Parámetros de proyecto para centralizar rutas.
- Autenticación de Windows para evitar credenciales hardcodeadas.
- Separación explícita entre registros válidos y rechazados.
- Motivos de rechazo identificables.
- Redirección de errores de conversión sin detener todo el ETL.
- Restricción de precedencia entre validación del entorno y procesamiento.
- Uso de tipos compatibles entre SSIS y SQL Server.
- Archivo de rechazados independiente para revisión posterior.

---

## Mejoras futuras

El alcance actual cumple con el entregable planteado. Como mejoras posteriores se podrían incorporar:

- Tabla de staging.
- Auditoría de ejecuciones.
- Control de archivos procesados.
- Prevención de duplicados mediante Lookup por `IdVenta`.
- Carga incremental.
- Logging centralizado.
- Notificaciones ante errores.
- Archivado automático del archivo de entrada mediante Tarea Sistema de archivos.

---

## Tecnologías utilizadas

- Microsoft SQL Server
- SQL Server Integration Services (SSIS)
- SQL Server Management Studio
- Visual Studio Community
- SQL Server Integration Services Projects
- Git / GitHub
