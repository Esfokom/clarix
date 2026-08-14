use clarix_editing_core::{
    CommandEnvelope, CommandId, DocumentId, DocumentModel, DocumentObject, DocumentRevision,
    EditorCommand, EditorSessionActor, EditorSessionState, ObjectId, PageId, PageNode, PdfBox,
    SessionId, TextBlock, Utf16Range,
};
use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};

fn model() -> (DocumentModel, ObjectId) {
    let page_id = PageId::from_source_key("benchmark/page/1");
    let object_id = ObjectId::from_source_key("benchmark/page/1/text/1");
    let model = DocumentModel::new(
        DocumentId::from_source_key("benchmark"),
        "sha256:benchmark".into(),
        vec![PageNode::new(
            page_id,
            1,
            612.0,
            792.0,
            vec![DocumentObject::Text(TextBlock::plain(
                object_id,
                page_id,
                "A",
                PdfBox::new(0.0, 0.0, 20.0, 20.0).unwrap(),
            ))],
        )],
    )
    .unwrap();
    (model, object_id)
}

fn replace(object_id: ObjectId) -> EditorCommand {
    EditorCommand::ReplaceTextRange {
        object_id,
        range: Utf16Range::new(0, 1).unwrap(),
        replacement: "B".into(),
    }
}

fn command_latency(c: &mut Criterion) {
    c.bench_function("command_latency/direct_submit", |b| {
        b.iter_batched(
            || {
                let (model, object_id) = model();
                (EditorSessionState::new(SessionId::new(), model), object_id)
            },
            |(mut session, object_id)| {
                black_box(
                    session
                        .submit(CommandEnvelope::user(
                            CommandId::new(),
                            session.revision(),
                            replace(object_id),
                        ))
                        .unwrap(),
                );
            },
            BatchSize::SmallInput,
        )
    });
}

fn actor_round_trip(c: &mut Criterion) {
    c.bench_function("actor_round_trip/submit", |b| {
        b.iter_batched(
            || {
                let (model, object_id) = model();
                (EditorSessionActor::spawn(model), object_id)
            },
            |(actor, object_id)| {
                black_box(
                    actor
                        .submit(CommandEnvelope::user(
                            CommandId::new(),
                            DocumentRevision::INITIAL,
                            replace(object_id),
                        ))
                        .unwrap(),
                );
                actor.close().unwrap();
            },
            BatchSize::SmallInput,
        )
    });
}

fn stable_id_derivation(c: &mut Criterion) {
    c.bench_function("stable_id_derivation/10000", |b| {
        b.iter(|| {
            for index in 0..10_000 {
                black_box(ObjectId::from_source_key(&format!("page/1/object/{index}")));
            }
        })
    });
}

criterion_group!(
    benches,
    command_latency,
    actor_round_trip,
    stable_id_derivation
);
criterion_main!(benches);
