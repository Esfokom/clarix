use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Deserializer, Serialize};
use thiserror::Error;

use crate::{
    AffineTransform, DocumentId, DocumentRevision, ObjectId, PageId, PdfBox, TextRun, TextStyle,
    Utf16Range,
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
        }
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
reserved_node!(AnnotationNode);
reserved_node!(OcrLayer);

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
    Text(TextBlock),
    Image(ImageNode),
    Vector(VectorNode),
    Annotation(AnnotationNode),
    OcrLayer(OcrLayer),
    Group(GroupNode),
}

impl DocumentObject {
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

    pub(crate) fn replace_object(&mut self, object: DocumentObject) -> Result<(), ModelError> {
        let id = object.id();
        let Some((page_index, object_offset)) = self.object_index.get(&id).copied() else {
            return Err(ModelError::MissingObject(id));
        };
        self.pages[page_index].objects[object_offset] = object;
        Ok(())
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
}
