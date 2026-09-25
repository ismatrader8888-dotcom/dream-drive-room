<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

- Parse Brazilian PIX amounts as decimal reais (dots are thousands separators, commas are cents), enforce the provider's R$ 10.000 ceiling on client and server, and reject mismatched provider responses; this prevents QR codes with a smaller value than the requested deposit.
- Schedule vehicle and charging-station rewards on São Paulo weekdays at the purchase-time clock hour, skipping Saturdays and Sundays; this preserves 25/30 paid cycles and keeps existing rewards untouched.
