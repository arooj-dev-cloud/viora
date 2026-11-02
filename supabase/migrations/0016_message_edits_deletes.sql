grant update (body, edited_at), delete on public.messages to authenticated;

create policy "Authors edit their own messages"
on public.messages for update to authenticated
using (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id)
)
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id)
);

create policy "Authors delete their own messages"
on public.messages for delete to authenticated
using (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id)
);
