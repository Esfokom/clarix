use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Deserializer, Serialize};
use thiserror::Error;

use crate::{
    validate_utf16_range, AffineTransform, DocumentId, DocumentRevision, FontRef, ObjectId, PageId,
    PdfBox, SourceGlyph, TextAnchor, TextLayoutRecipe, TextRun, TextStyle, Utf16Range,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EditCapability {
    Editable,
    OverlayOnly,
    ReadOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectKind {
    Text,
    Image,
    Vector,
    Annotation,
    OcrLayer,
    Group,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityReason {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceBinding {
    pub adapter_id: String,
    pub source_revision: String,
    pub source_key: String,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct NodeBase {
    id: ObjectId,
    page_id: PageId,
    bounds: PdfBox,
    transform: AffineTransform,
    capability: EditCapability,
    created_revision: DocumentRevision,
    modified_revision: DocumentRevision,
    source_binding: Option<SourceBinding>,
}

impl NodeBase {
    fn new(id: ObjectId, page_id: PageId, bounds: PdfBox, capability: EditCapability) -> Self {
        Self {
            id,
            page_id,
            bounds,
            transform: AffineTransform::IDENTITY,
            capability,
            created_revision: DocumentRevision::INITIAL,
            modified_revision: DocumentRevision::INITIAL,
            source_binding: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TextBlock {
    #[serde(flatten)]
    base: NodeBase,
    pub text: String,
    pub runs: Vec<TextRun>,
    pub font: Option<FontRef>,
    pub layout: TextLayoutRecipe,
    pub source_glyphs: Vec<SourceGlyph>,
    #[serde(default)]
    pub character_boxes: Vec<crate::TextCharacterBox>,
    #[serde(default)]
    pub layout_capacity_graphemes: u32,
    pub capability_reason: Option<CapabilityReason>,
}

impl TextBlock {
    pub fn plain(id: ObjectId, page_id: PageId, text: impl Into<String>, bounds: PdfBox) -> Self {
        let text = text.into();
        let utf16_length = text.encode_utf16().count() as u32;
        Self {
            base: NodeBase::new(id, page_id, bounds, EditCapability::Editable),
            text,
            runs: vec![TextRun {
                range: Utf16Range::new(0, utf16_length).expect("plain text range is ordered"),
                style: TextStyle::default(),
            }],
            font: None,
            layout: TextLayoutRecipe::default(),
            source_glyphs: Vec::new(),
            character_boxes: Vec::new(),
            layout_capacity_graphemes: 0,
            capability_reason: None,
        }
    }

    pub fn with_source_binding(mut self, source_binding: SourceBinding) -> Self {
        self.base.source_binding = Some(source_binding);
        self
    }

    pub fn with_transform(mut self, transform: AffineTransform) -> Self {
        self.base.transform = transform;
        self
    }

    pub fn with_text_contract(
        mut self,
        font: FontRef,
        layout: TextLayoutRecipe,
        source_glyphs: Vec<SourceGlyph>,
    ) -> Self {
        self.font = Some(font);
        self.layout = layout;
        self.source_glyphs = source_glyphs;
        self
    }

    pub fn with_character_boxes(mut self, character_boxes: Vec<crate::TextCharacterBox>) -> Self {
        if self.layout_capacity_graphemes == 0 {
            self.layout_capacity_graphemes = character_boxes.len() as u32;
        }
        self.character_boxes = character_boxes;
        self
    }

    pub fn with_capability(
        mut self,
        capability: EditCapability,
        reason: Option<CapabilityReason>,
    ) -> Self {
        self.base.capability = capability;
        self.capability_reason = reason;
        self
    }

    pub fn capability(&self) -> EditCapability {
        self.base.capability
    }

    pub fn font(&self) -> Option<&FontRef> {
        self.font.as_ref()
    }

    pub fn capability_reason(&self) -> Option<&CapabilityReason> {
        self.capability_reason.as_ref()
    }
}

macro_rules! reserved_node {
    ($name:ident) => {
        #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
        pub struct $name {
            #[serde(flatten)]
            base: NodeBase,
            pub source_label: Option<String>,
        }

        impl $name {
            pub fn reserved(
                id: ObjectId,
                page_id: PageId,
                bounds: PdfBox,
                source_label: Option<String>,
            ) -> Self {
                Self {
                    base: NodeBase::new(id, page_id, bounds, EditCapability::ReadOnly),
                    source_label,
                }
            }
        }
    };
}

reserved_node!(ImageNode);
reserved_node!(VectorNode);
reserved_node!(OcrLayer);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AnnotationKind {
    Bookmark,
    Highlight,
    Comment,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnnotationTextRange {
    pub range_id: String,
    pub object_id: ObjectId,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub quoted_text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum AnnotationAnchor {
    PagePoint { x: f64, y: f64 },
    Text { ranges: Vec<AnnotationTextRange> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AnnotationNode {
    #[serde(flatten)]
    base: NodeBase,
    pub kind: AnnotationKind,
    pub anchor: AnnotationAnchor,
    pub title: String,
    pub body: String,
    pub color_rgba: [u8; 4],
    pub opacity: f32,
    pub resolved: bool,
}

impl AnnotationNode {
    pub fn comment(
        id: ObjectId,
        page_id: PageId,
        bounds: PdfBox,
        anchor: AnnotationAnchor,
        body: impl Into<String>,
    ) -> Self {
        Self {
            base: NodeBase::new(id, page_id, bounds, EditCapability::Editable),
            kind: AnnotationKind::Comment,
            anchor,
            title: String::new(),
            body: body.into(),
            color_rgba: [255, 212, 59, 255],
            opacity: 1.0,
            resolved: false,
        }
    }

    pub fn range_count(&self) -> usize {
        match &self.anchor {
            AnnotationAnchor::PagePoint { .. } => 0,
            AnnotationAnchor::Text { ranges } => ranges.len(),
        }
    }

    pub fn id(&self) -> ObjectId {
        self.base.id
    }

    pub fn page_id(&self) -> PageId {
        self.base.page_id
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GroupNode {
    #[serde(flatten)]
    base: NodeBase,
    pub children: Vec<ObjectId>,
}

impl GroupNode {
    pub fn reserved(
        id: ObjectId,
        page_id: PageId,
        bounds: PdfBox,
        children: Vec<ObjectId>,
    ) -> Self {
        Self {
            base: NodeBase::new(id, page_id, bounds, EditCapability::ReadOnly),
            children,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum DocumentObject {
    Text(Box<TextBlock>),
    Image(ImageNode),
    Vector(VectorNode),
    Annotation(AnnotationNode),
    OcrLayer(OcrLayer),
    Group(GroupNode),
}

impl DocumentObject {
    pub fn text(block: TextBlock) -> Self {
        Self::Text(Box::new(block))
    }

    fn base(&self) -> &NodeBase {
        match self {
            Self::Text(node) => &node.base,
            Self::Image(node) => &node.base,
            Self::Vector(node) => &node.base,
            Self::Annotation(node) => &node.base,
            Self::OcrLayer(node) => &node.base,
            Self::Group(node) => &node.base,
        }
    }

    fn base_mut(&mut self) -> &mut NodeBase {
        match self {
            Self::Text(node) => &mut node.base,
            Self::Image(node) => &mut node.base,
            Self::Vector(node) => &mut node.base,
            Self::Annotation(node) => &mut node.base,
            Self::OcrLayer(node) => &mut node.base,
            Self::Group(node) => &mut node.base,
        }
    }

    pub fn id(&self) -> ObjectId {
        self.base().id
    }

    pub fn page_id(&self) -> PageId {
        self.base().page_id
    }

    pub fn bounds(&self) -> PdfBox {
        self.base().bounds
    }

    pub fn transform(&self) -> AffineTransform {
        self.base().transform
    }

    pub fn capability(&self) -> EditCapability {
        self.base().capability
    }

    pub fn created_revision(&self) -> DocumentRevision {
        self.base().created_revision
    }

    pub fn modified_revision(&self) -> DocumentRevision {
        self.base().modified_revision
    }

    pub fn source_binding(&self) -> Option<&SourceBinding> {
        self.base().source_binding.as_ref()
    }

    pub(crate) fn set_bounds(&mut self, bounds: PdfBox) {
        self.base_mut().bounds = bounds;
    }

    pub(crate) fn set_transform(&mut self, transform: AffineTransform) {
        self.base_mut().transform = transform;
    }

    pub(crate) fn set_modified_revision(&mut self, revision: DocumentRevision) {
        self.base_mut().modified_revision = revision;
    }

    pub const fn kind(&self) -> ObjectKind {
        match self {
            Self::Text(_) => ObjectKind::Text,
            Self::Image(_) => ObjectKind::Image,
            Self::Vector(_) => ObjectKind::Vector,
            Self::Annotation(_) => ObjectKind::Annotation,
            Self::OcrLayer(_) => ObjectKind::OcrLayer,
            Self::Group(_) => ObjectKind::Group,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PageNode {
    pub id: PageId,
    pub page_number: u32,
    pub width: f64,
    pub height: f64,
    pub objects: Vec<DocumentObject>,
}

impl PageNode {
    pub fn new(
        id: PageId,
        page_number: u32,
        width: f64,
        height: f64,
        objects: Vec<DocumentObject>,
    ) -> Self {
        Self {
            id,
            page_number,
            width,
            height,
            objects,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DocumentModel {
    pub id: DocumentId,
    pub source_fingerprint: String,
    pub revision: DocumentRevision,
    pub pages: Vec<PageNode>,
    #[serde(skip)]
    object_index: HashMap<ObjectId, (usize, usize)>,
}

impl DocumentModel {
    pub fn new(
        id: DocumentId,
        source_fingerprint: String,
        pages: Vec<PageNode>,
    ) -> Result<Self, ModelError> {
        Self::from_parts(id, source_fingerprint, DocumentRevision::INITIAL, pages)
    }

    pub fn rebase_source(&mut self, source_fingerprint: impl Into<String>) {
        let source_fingerprint = source_fingerprint.into();
        self.source_fingerprint.clone_from(&source_fingerprint);
        for page in &mut self.pages {
            for object in &mut page.objects {
                if let Some(binding) = &mut object.base_mut().source_binding {
                    binding.source_revision.clone_from(&source_fingerprint);
                }
            }
        }
    }

    fn from_parts(
        id: DocumentId,
        source_fingerprint: String,
        revision: DocumentRevision,
        pages: Vec<PageNode>,
    ) -> Result<Self, ModelError> {
        let mut page_numbers = HashSet::new();
        let mut page_ids = HashSet::new();
        let mut object_index = HashMap::new();

        for (page_index, page) in pages.iter().enumerate() {
            if page.page_number == 0 || !page_numbers.insert(page.page_number) {
                return Err(ModelError::DuplicatePageNumber(page.page_number));
            }
            if !page_ids.insert(page.id) {
                return Err(ModelError::DuplicatePageId(page.id));
            }
            if !page.width.is_finite()
                || !page.height.is_finite()
                || page.width <= 0.0
                || page.height <= 0.0
            {
                return Err(ModelError::InvalidPageDimensions(page.page_number));
            }
            for (object_offset, object) in page.objects.iter().enumerate() {
                if object.page_id() != page.id {
                    return Err(ModelError::ObjectOnWrongPage(object.id()));
                }
                if object_index
                    .insert(object.id(), (page_index, object_offset))
                    .is_some()
                {
                    return Err(ModelError::DuplicateObjectId(object.id()));
                }
                if let DocumentObject::Text(block) = object {
                    validate_text_block(block)?;
                }
            }
        }

        for page in &pages {
            for object in &page.objects {
                if let DocumentObject::Group(group) = object {
                    for child_id in &group.children {
                        let Some((child_page_index, _)) = object_index.get(child_id) else {
                            return Err(ModelError::MissingGroupChild(*child_id));
                        };
                        if pages[*child_page_index].id != page.id {
                            return Err(ModelError::CrossPageGroupChild(*child_id));
                        }
                    }
                }
            }
        }

        Ok(Self {
            id,
            source_fingerprint,
            revision,
            pages,
            object_index,
        })
    }

    pub fn object(&self, id: ObjectId) -> Option<&DocumentObject> {
        let (page_index, object_offset) = *self.object_index.get(&id)?;
        self.pages.get(page_index)?.objects.get(object_offset)
    }

    pub fn page(&self, page_number: u32) -> Option<&PageNode> {
        self.pages
            .iter()
            .find(|page| page.page_number == page_number)
    }

    pub(crate) fn hydrate_page(&mut self, page: PageNode) -> Result<(), ModelError> {
        if let Some(existing) = self.page(page.page_number) {
            return if existing == &page {
                Ok(())
            } else {
                Err(ModelError::HydratedPageConflict(page.page_number))
            };
        }
        let mut pages = self.pages.clone();
        pages.push(page);
        pages.sort_by_key(|page| page.page_number);
        *self = Self::from_parts(
            self.id,
            self.source_fingerprint.clone(),
            self.revision,
            pages,
        )?;
        Ok(())
    }

    pub(crate) fn replace_object(&mut self, object: DocumentObject) -> Result<(), ModelError> {
        let id = object.id();
        let Some((page_index, object_offset)) = self.object_index.get(&id).copied() else {
            return Err(ModelError::MissingObject(id));
        };
        self.pages[page_index].objects[object_offset] = object;
        Ok(())
    }

    pub(crate) fn insert_object(&mut self, object: DocumentObject) -> Result<(), ModelError> {
        if self.object_index.contains_key(&object.id()) {
            return Err(ModelError::DuplicateObjectId(object.id()));
        }
        let Some(page_index) = self
            .pages
            .iter()
            .position(|page| page.id == object.page_id())
        else {
            return Err(ModelError::MissingPage(object.page_id()));
        };
        let mut pages = self.pages.clone();
        pages[page_index].objects.push(object);
        *self = Self::from_parts(
            self.id,
            self.source_fingerprint.clone(),
            self.revision,
            pages,
        )?;
        Ok(())
    }

    pub(crate) fn remove_object(&mut self, id: ObjectId) -> Result<DocumentObject, ModelError> {
        let Some((page_index, object_offset)) = self.object_index.get(&id).copied() else {
            return Err(ModelError::MissingObject(id));
        };
        let mut pages = self.pages.clone();
        let object = pages[page_index].objects.remove(object_offset);
        *self = Self::from_parts(
            self.id,
            self.source_fingerprint.clone(),
            self.revision,
            pages,
        )?;
        Ok(object)
    }

    pub fn replay_objects(
        &self,
        objects: impl IntoIterator<Item = DocumentObject>,
        revision: DocumentRevision,
    ) -> Result<Self, ModelError> {
        let mut replayed = self.clone();
        for object in objects {
            if replayed.object(object.id()).is_some() {
                replayed.replace_object(object)?;
            } else {
                replayed.insert_object(object)?;
            }
        }
        replayed.set_revision(revision);
        Self::from_parts(
            replayed.id,
            replayed.source_fingerprint,
            replayed.revision,
            replayed.pages,
        )
    }

    pub(crate) fn set_revision(&mut self, revision: DocumentRevision) {
        self.revision = revision;
    }
}

impl<'de> Deserialize<'de> for DocumentModel {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct SerializedModel {
            id: DocumentId,
            source_fingerprint: String,
            revision: DocumentRevision,
            pages: Vec<PageNode>,
        }

        let model = SerializedModel::deserialize(deserializer)?;
        Self::from_parts(
            model.id,
            model.source_fingerprint,
            model.revision,
            model.pages,
        )
        .map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, PartialEq, Error)]
pub enum ModelError {
    #[error("duplicate page number {0}")]
    DuplicatePageNumber(u32),
    #[error("duplicate page ID {0}")]
    DuplicatePageId(PageId),
    #[error("page {0} has invalid dimensions")]
    InvalidPageDimensions(u32),
    #[error("duplicate object ID {0}")]
    DuplicateObjectId(ObjectId),
    #[error("object {0} belongs to a different page")]
    ObjectOnWrongPage(ObjectId),
    #[error("group references missing child {0}")]
    MissingGroupChild(ObjectId),
    #[error("group references child {0} on a different page")]
    CrossPageGroupChild(ObjectId),
    #[error("object {0} does not exist")]
    MissingObject(ObjectId),
    #[error("page {0} does not exist")]
    MissingPage(PageId),
    #[error("page {0} was already hydrated with different content")]
    HydratedPageConflict(u32),
    #[error("editable imported text {0} has no complete font/materialization contract")]
    IncompleteEditableText(ObjectId),
    #[error("text object {0} has an invalid layout recipe")]
    InvalidTextLayout(ObjectId),
    #[error("text object {0} has invalid or incomplete runs")]
    InvalidTextRuns(ObjectId),
    #[error("text object {0} has invalid or incomplete character geometry")]
    InvalidCharacterGeometry(ObjectId),
    #[error("non-editable text object {0} has no capability reason")]
    MissingCapabilityReason(ObjectId),
}

fn validate_text_block(block: &TextBlock) -> Result<(), ModelError> {
    let id = block.base.id;
    if !block.layout.is_valid() {
        return Err(ModelError::InvalidTextLayout(id));
    }
    let text_length = block.text.encode_utf16().count() as u32;
    let mut expected_start = 0;
    for run in &block.runs {
        if run.range.start != expected_start
            || validate_utf16_range(&block.text, run.range).is_err()
            || !run.style.font_size.is_finite()
            || run.style.font_size <= 0.0
        {
            return Err(ModelError::InvalidTextRuns(id));
        }
        expected_start = run.range.end;
    }
    if expected_start != text_length || block.runs.is_empty() {
        return Err(ModelError::InvalidTextRuns(id));
    }
    if !block.character_boxes.is_empty() {
        if block.layout_capacity_graphemes != 0
            && block.layout_capacity_graphemes < block.character_boxes.len() as u32
        {
            return Err(ModelError::InvalidCharacterGeometry(id));
        }
        let mut expected_start = 0;
        for character in &block.character_boxes {
            if character.range.start != expected_start
                || character.range.is_empty()
                || validate_utf16_range(&block.text, character.range).is_err()
                || TextAnchor::new(
                    id,
                    &block.text,
                    character.range.start,
                    crate::TextAffinity::Downstream,
                )
                .is_err()
                || TextAnchor::new(
                    id,
                    &block.text,
                    character.range.end,
                    crate::TextAffinity::Upstream,
                )
                .is_err()
            {
                return Err(ModelError::InvalidCharacterGeometry(id));
            }
            expected_start = character.range.end;
        }
        if expected_start != text_length {
            return Err(ModelError::InvalidCharacterGeometry(id));
        }
    }
    if block.base.source_binding.is_some() && block.base.capability == EditCapability::Editable {
        let complete = block
            .font
            .as_ref()
            .is_some_and(|font| font.is_valid() && font.embeddable)
            && !block.source_glyphs.is_empty()
            && (block.text.is_empty() || !block.character_boxes.is_empty());
        if !complete {
            return Err(ModelError::IncompleteEditableText(id));
        }
    }
    if block.base.capability != EditCapability::Editable && block.capability_reason.is_none() {
        return Err(ModelError::MissingCapabilityReason(id));
    }
    Ok(())
}
