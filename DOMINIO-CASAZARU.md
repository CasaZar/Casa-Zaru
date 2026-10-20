# ¿Pueden la Gestión y el Cotizador vivir en casazaru.cl?

> Brief para María José (20-10-2026). Pégalo tal cual en tu Claude Code como primer
> mensaje. Está escrito para alguien que no es técnico; Claude lo entiende igual.

## Respuesta corta

**Sí, y la mitad ya está hecha.**

- El **Cotizador** ya vive en **https://cotizador.casazaru.cl**. Eso es casazaru.cl.
- La **Gestión** todavía está en una dirección de GitHub
  (`casazar.github.io/Casa-Zaru/`). Se puede pasar a **https://gestion.casazaru.cl**
  con el mismo truco que ya usa el Cotizador. Es un cambio de DNS en Cloudflare más
  un archivo de una línea en el repo. Sin costo.

## Lo que NO conviene hacer

**No meter las apps dentro de www.casazaru.cl.** Esa dirección es la tienda
(Shopify). Si se le pisa, se cae la tienda. Las apps van en *subdominios*:
`cotizador.casazaru.cl`, `gestion.casazaru.cl`. Es la forma normal de hacerlo y
la tienda ni se entera.

## Cómo está armado hoy (verificado el 20-10-2026 con nslookup)

| Dirección | A dónde apunta | Qué es |
|---|---|---|
| `casazaru.cl` y `www.casazaru.cl` | Shopify | La tienda. **No tocar.** |
| `cotizador.casazaru.cl` | GitHub Pages (CNAME → `casazar.github.io`) | El cotizador público. Ya en el dominio. |
| `casazar.github.io/Casa-Zaru/` | GitHub Pages | La Gestión. Falta ponerle `gestion.casazaru.cl`. |

El DNS del dominio lo maneja **Cloudflare** (servidores `jo` y `lynn.ns.cloudflare.com`).
Las dos apps se publican gratis con GitHub Pages desde la cuenta `CasaZar`; un `git push`
redeploya solo.

## Pasos para mover la Gestión a gestion.casazaru.cl

Son cuatro, en este orden. Ninguno rompe nada si se hace a medias: la dirección
vieja sigue funcionando hasta el paso 3.

1. **Cloudflare → DNS.** Agregar un registro:
   - Tipo `CNAME`, nombre `gestion`, destino `casazar.github.io`.
   - **Proxy apagado** (nube gris, «DNS only»). Con la nube naranja GitHub no logra
     emitir el certificado HTTPS. El de `cotizador` seguramente está igual: copiarlo.
2. **Repo `Casa-Zaru` en GitHub → Settings → Pages → Custom domain:** escribir
   `gestion.casazaru.cl` y guardar. GitHub crea solo un archivo `CNAME` en el repo
   con esa línea. Esperar a que diga «DNS check successful» y marcar
   **Enforce HTTPS** (puede tardar de minutos a una hora).
3. **Supabase, proyecto de la Gestión** (ref `padnttpgzuotxeipjrry`, en el panel se
   llama «ZARU · Gestión»): Authentication → URL Configuration.
   - Site URL: `https://gestion.casazaru.cl`
   - Redirect URLs: agregar `https://gestion.casazaru.cl/**` (dejar también la vieja
     mientras tanto). Sin esto, el correo de «olvidé mi contraseña» manda a la
     dirección antigua.
4. **Avisar al equipo** la dirección nueva. El acceso viejo sigue andando un tiempo
   (GitHub redirige), así que no hay apuro en borrar marcadores.

## Qué NO hace falta tocar

- **El código de la Gestión.** No tiene la dirección de GitHub escrita adentro
  (verificado con grep: cero coincidencias de `casazar.github.io` en `index.html`).
- **El Cotizador.** Ya está en su subdominio; sus funciones de servidor (Starken,
  Shopify) ya aceptan solo `https://cotizador.casazaru.cl`.
- **Nada de Shopify.** La tienda no se entera.

## Dos advertencias

- **El repo `Casa-Zaru` tiene que seguir público.** GitHub Pages gratis no publica
  repos privados: si alguien lo pone privado, la Gestión cae con 404 al instante,
  con o sin dominio. Ser público no expone datos: lo que protege la Gestión es el
  login + las reglas RLS de Supabase, no la URL.
- **Alternativa si GitHub Pages molesta:** el repo trae un `netlify.toml` listo que
  publica solo el HTML. Netlify también acepta dominios propios vía Cloudflare. Es
  plan B; no hace falta hoy.

## Para verificar que quedó bien

En cualquier terminal:

```
nslookup -type=CNAME gestion.casazaru.cl
```

Debe responder `casazar.github.io`. Después abrir `https://gestion.casazaru.cl`,
entrar con un usuario y ver que carga la lista de pedidos.
